*----------------------------------------------------------------------*
* Clean Core Level A (ABAP for Cloud Development) Replacement
* Replaces legacy SEGW class ZCL_ZPP_SERVICES_DPC_EXT (file.md)
*
* Cloudification Repository Verification (100% Released Level A APIs):
*   - DDLS: I_WorkCenter, I_StandardWorkFmlaParamGroup,
*           I_StandardWorkFormulaParamText, I_OrderType, I_OrderTypeText
*   - INTF: IF_RAP_QUERY_PROVIDER, IF_RAP_QUERY_REQUEST,
*           IF_RAP_QUERY_RESPONSE, IF_RAP_QUERY_FILTER
*   - CLAS: CL_ABAP_CONTEXT_INFO, CX_RAP_QUERY_PROVIDER,
*           CX_RAP_QUERY_FILTER_NO_RANGE
*   - DTEL: PPH_ARBPL, WERKS_D, PPH_PARID, PPH_PARTXT, AUART,
*           PPH_AUTYP, PPH_AUARTTEXT, SPRAS
*----------------------------------------------------------------------*

*======================================================================*
* 1. CDS Entity for Work Center Formula Parameters (ZI_PP_WRKCTRPARAMS)
*    Replaces: GETWRKCTRPARAMSS_GET_ENTITY & GETWRKCTRPARAMSS_GET_ENTITYSET
*    Supports both single-key OData read and full query/filter/paging!
*======================================================================*
@EndUserText.label: 'Work Center Formula Parameters'
@ObjectModel.query.implementedBy: 'ABAP:ZCL_PP_WRKCTR_PARAMS_QP'
define custom entity ZI_PP_WrkCtrParams
{
  key WrkCtr : pph_arbpl;
  key Plant  : werks_d;
      Param1 : pph_partxt;
      Param2 : pph_partxt;
      Param3 : pph_partxt;
      Param4 : pph_partxt;
      Param5 : pph_partxt;
      Param6 : pph_partxt;
}


*======================================================================*
* 2. CDS View Entity for Order Types (ZI_PP_WO_TYPE)
*    Replaces: WO_TYPESET_GET_ENTITYSET (T003O, T003P, ZPM_GET_USER_LANG)
*    Zero custom ABAP needed — HANA executes filter, join & paging natively
*======================================================================*
@AccessControl.authorizationCheck: #NOT_REQUIRED
@EndUserText.label: 'Work / Production Order Types'
@Metadata.ignorePropagatedAnnotations: true
define view entity ZI_PP_WO_Type
  as select from I_OrderType as OrderType
    left outer to one join I_OrderTypeText as _Text
      on  OrderType.OrderType = _Text.OrderType
      and _Text.Language      = $session.system_language
{
  key OrderType.OrderType     as Auart,
      OrderType.OrderCategory as Autyp,
      _Text.OrderTypeName     as Txt
}


*======================================================================*
* 3. RAP Service Definition (ZUI_PP_SERVICES)
*    Expose via Service Binding (SRVB) as OData V2 or OData V4 UI/Web API
*======================================================================*
@EndUserText.label: 'PP Clean Core Services'
define service ZUI_PP_Services {
  expose ZI_PP_WrkCtrParams as GetWrkCtrParamsSet;
  expose ZI_PP_WO_Type      as WO_TypeSet;
}


*======================================================================*
* 4. ABAP Cloud Query Provider Class (ZCL_PP_WRKCTR_PARAMS_QP)
*    Language Version: ABAP for Cloud Development (Clean Core Level A)
*======================================================================*
CLASS zcl_pp_wrkctr_params_qp DEFINITION
  PUBLIC
  FINAL
  CREATE PUBLIC.

  PUBLIC SECTION.
    INTERFACES if_rap_query_provider.

  PRIVATE SECTION.
    CONSTANTS gc_work_center_type TYPE c LENGTH 1 VALUE 'A'.
    CONSTANTS gc_rule_should_enter TYPE c LENGTH 1 VALUE '2'.

    TYPES:
      BEGIN OF ty_wrkctr_src,
        wrkctr TYPE pph_arbpl,
        plant  TYPE werks_d,
        vgm01  TYPE c LENGTH 1,
        vgm02  TYPE c LENGTH 1,
        vgm03  TYPE c LENGTH 1,
        vgm04  TYPE c LENGTH 1,
        vgm05  TYPE c LENGTH 1,
        vgm06  TYPE c LENGTH 1,
        par01  TYPE pph_parid,
        par02  TYPE pph_parid,
        par03  TYPE pph_parid,
        par04  TYPE pph_parid,
        par05  TYPE pph_parid,
        par06  TYPE pph_parid,
      END OF ty_wrkctr_src,
      tt_wrkctr_src TYPE STANDARD TABLE OF ty_wrkctr_src WITH EMPTY KEY,

      BEGIN OF ty_param_text,
        parid   TYPE pph_parid,
        parname TYPE pph_partxt,
      END OF ty_param_text,
      tt_param_text TYPE HASHED TABLE OF ty_param_text WITH UNIQUE KEY parid,

      tt_result TYPE STANDARD TABLE OF zi_pp_wrkctrparams WITH EMPTY KEY.

    METHODS resolve_param_text
      IMPORTING
        iv_rule         TYPE c
        iv_parid        TYPE pph_parid
        it_param_texts  TYPE tt_param_text
      RETURNING
        VALUE(rv_label) TYPE pph_partxt.
ENDCLASS.



CLASS zcl_pp_wrkctr_params_qp IMPLEMENTATION.

  METHOD if_rap_query_provider~select.
    DATA lr_wrkctr TYPE RANGE OF pph_arbpl.
    DATA lr_plant  TYPE RANGE OF werks_d.
    DATA lr_params TYPE RANGE OF pph_parid.
    DATA lt_param_texts TYPE tt_param_text.
    DATA lt_result TYPE tt_result.

    " 1. Extract OData key / $filter ranges via released RAP Filter API
    TRY.
        DATA(lt_filter_ranges) = io_request->get_filter( )->get_as_ranges( ).
      CATCH cx_rap_query_filter_no_range INTO DATA(lx_no_range).
        RAISE EXCEPTION TYPE cx_rap_query_provider
          EXPORTING
            previous = lx_no_range.
    ENDTRY.

    LOOP AT lt_filter_ranges INTO DATA(ls_filter).
      CASE to_upper( ls_filter-name ).
        WHEN 'WRKCTR'.
          lr_wrkctr = CORRESPONDING #( ls_filter-range ).
        WHEN 'PLANT'.
          lr_plant  = CORRESPONDING #( ls_filter-range ).
      ENDCASE.
    ENDLOOP.

    " 2. Paging parameters (handles $top, $skip, and single-entity read)
    DATA(lv_offset)    = io_request->get_paging( )->get_offset( ).
    DATA(lv_page_size) = io_request->get_paging( )->get_page_size( ).
    DATA(lv_max_rows)  = COND i(
      WHEN lv_page_size = if_rap_query_paging=>page_size_unlimited THEN 0
      ELSE lv_page_size ).

    " 3. Handle $count-only requests if needed
    IF io_request->is_total_numb_of_rec_requested( ).
      SELECT COUNT( * )
        FROM I_WorkCenter AS wc
        INNER JOIN I_StandardWorkFmlaParamGroup AS grp
          ON wc~StandardWorkFormulaParamGroup = grp~StandardWorkFormulaParamGroup
        WHERE wc~WorkCenter         IN @lr_wrkctr
          AND wc~Plant              IN @lr_plant
          AND wc~WorkCenterTypeCode =  @gc_work_center_type
        INTO @DATA(lv_total_count).

      io_response->set_total_number_of_records( lv_total_count ).
    ENDIF.

    IF NOT io_request->is_data_requested( ).
      RETURN.
    ENDIF.

    " 4. Select Work Center & Standard Value Key parameters via Level A CDS views
    "    Replaces unreleased CRHD + TC21 join and prevents short dump on 0 rows
    SELECT wc~WorkCenter                    AS wrkctr,
           wc~Plant                         AS plant,
           wc~WrkCtrStdValMaintRule1        AS vgm01,
           wc~WrkCtrStdValMaintRule2        AS vgm02,
           wc~WrkCtrStdValMaintRule3        AS vgm03,
           wc~WrkCtrStdValMaintRule4        AS vgm04,
           wc~WrkCtrStdValMaintRule5        AS vgm05,
           wc~WrkCtrStdValMaintRule6        AS vgm06,
           grp~StandardWorkFormulaParam1    AS par01,
           grp~StandardWorkFormulaParam2    AS par02,
           grp~StandardWorkFormulaParam3    AS par03,
           grp~StandardWorkFormulaParam4    AS par04,
           grp~StandardWorkFormulaParam5    AS par05,
           grp~StandardWorkFormulaParam6    AS par06
      FROM I_WorkCenter AS wc
      INNER JOIN I_StandardWorkFmlaParamGroup AS grp
        ON wc~StandardWorkFormulaParamGroup = grp~StandardWorkFormulaParamGroup
      WHERE wc~WorkCenter         IN @lr_wrkctr
        AND wc~Plant              IN @lr_plant
        AND wc~WorkCenterTypeCode =  @gc_work_center_type
      ORDER BY wc~WorkCenter, wc~Plant
      INTO TABLE @DATA(lt_wkctr)
      OFFSET @lv_offset
      UP TO @lv_max_rows ROWS.

    IF lt_wkctr IS INITIAL.
      io_response->set_data( lt_result ).
      RETURN.
    ENDIF.

    " 5. Collect only parameter IDs whose maintenance rule = '2'
    LOOP AT lt_wkctr INTO DATA(ls_wkctr).
      IF ls_wkctr-vgm01 = gc_rule_should_enter AND ls_wkctr-par01 IS NOT INITIAL.
        APPEND VALUE #( sign = 'I' option = 'EQ' low = ls_wkctr-par01 ) TO lr_params.
      ENDIF.
      IF ls_wkctr-vgm02 = gc_rule_should_enter AND ls_wkctr-par02 IS NOT INITIAL.
        APPEND VALUE #( sign = 'I' option = 'EQ' low = ls_wkctr-par02 ) TO lr_params.
      ENDIF.
      IF ls_wkctr-vgm03 = gc_rule_should_enter AND ls_wkctr-par03 IS NOT INITIAL.
        APPEND VALUE #( sign = 'I' option = 'EQ' low = ls_wkctr-par03 ) TO lr_params.
      ENDIF.
      IF ls_wkctr-vgm04 = gc_rule_should_enter AND ls_wkctr-par04 IS NOT INITIAL.
        APPEND VALUE #( sign = 'I' option = 'EQ' low = ls_wkctr-par04 ) TO lr_params.
      ENDIF.
      IF ls_wkctr-vgm05 = gc_rule_should_enter AND ls_wkctr-par05 IS NOT INITIAL.
        APPEND VALUE #( sign = 'I' option = 'EQ' low = ls_wkctr-par05 ) TO lr_params.
      ENDIF.
      IF ls_wkctr-vgm06 = gc_rule_should_enter AND ls_wkctr-par06 IS NOT INITIAL.
        APPEND VALUE #( sign = 'I' option = 'EQ' low = ls_wkctr-par06 ) TO lr_params.
      ENDIF.
    ENDLOOP.

    SORT lr_params BY low.
    DELETE ADJACENT DUPLICATES FROM lr_params COMPARING low.

    " 6. Read parameter descriptions ONLY when lr_params is non-empty
    "    Fixes critical empty-range bug, hardcoded 'E', and unreleased TC20T
    IF lr_params IS NOT INITIAL.
      DATA(lv_langu) = cl_abap_context_info=>get_system_language( ).

      SELECT StandardWorkFormulaParameter AS parid,
             StandardWorkFormulaParamName AS parname
        FROM I_StandardWorkFormulaParamText
        WHERE StandardWorkFormulaParameter IN @lr_params
          AND Language                     =  @lv_langu
        INTO TABLE @lt_param_texts.

      " Optional fallback to English if no text maintained in logon language
      IF lt_param_texts IS INITIAL AND lv_langu <> 'E'.
        SELECT StandardWorkFormulaParameter AS parid,
               StandardWorkFormulaParamName AS parname
          FROM I_StandardWorkFormulaParamText
          WHERE StandardWorkFormulaParameter IN @lr_params
            AND Language                     =  'E'
          INTO TABLE @lt_param_texts.
      ENDIF.
    ENDIF.

    " 7. Map response entities (only populates Param1..6 when rule = '2')
    LOOP AT lt_wkctr INTO ls_wkctr.
      APPEND VALUE #(
        wrkctr = ls_wkctr-wrkctr
        plant  = ls_wkctr-plant
        param1 = resolve_param_text( iv_rule = ls_wkctr-vgm01 iv_parid = ls_wkctr-par01 it_param_texts = lt_param_texts )
        param2 = resolve_param_text( iv_rule = ls_wkctr-vgm02 iv_parid = ls_wkctr-par02 it_param_texts = lt_param_texts )
        param3 = resolve_param_text( iv_rule = ls_wkctr-vgm03 iv_parid = ls_wkctr-par03 it_param_texts = lt_param_texts )
        param4 = resolve_param_text( iv_rule = ls_wkctr-vgm04 iv_parid = ls_wkctr-par04 it_param_texts = lt_param_texts )
        param5 = resolve_param_text( iv_rule = ls_wkctr-vgm05 iv_parid = ls_wkctr-par05 it_param_texts = lt_param_texts )
        param6 = resolve_param_text( iv_rule = ls_wkctr-vgm06 iv_parid = ls_wkctr-par06 it_param_texts = lt_param_texts )
      ) TO lt_result.
    ENDLOOP.

    io_response->set_data( lt_result ).
  ENDMETHOD.


  METHOD resolve_param_text.
    IF iv_rule <> gc_rule_should_enter OR iv_parid IS INITIAL.
      RETURN.
    ENDIF.

    ASSIGN it_param_texts[ parid = iv_parid ] TO FIELD-SYMBOL(<fs_txt>).
    IF sy-subrc = 0.
      rv_label = <fs_txt>-parname.
    ENDIF.
  ENDMETHOD.

ENDCLASS.
