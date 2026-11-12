*----------------------------------------------------------------------*
* Clean Core Level A (ABAP for Cloud Development) RAP Replacement
* Replaces legacy SEGW class ZCL_ZPM_DETAILS_DPC_EXT (PM_DETAILS)
*
* Architecture Follows SAP's Two-Stage Clean Core Governance Model:
*
* STAGE 1 — Retire Transactional / Single-Object Endpoints via
*           SAP Business Accelerator Hub (api.sap.com — Zero ABAP):
*   1. ConfirmationCancelHeader (Deep POST)
*      -> API_MAINTORDERCONFIRMATION (SAP_COM_0388):
*         POST /MaintOrderConfirmation(...)/CancelMaintOrderConfirmation
*   2. WoHeader + WorkorderoperationsSet (Deep POST)
*      -> CE_API_MAINTENANCEORDER_0002 / API_MAINTENANCEORDER;v=2
*         (PATCH /MaintenanceOrderOperation) + API_MAINTORDERCONFIRMATION
*         (POST /MaintOrderConfirmation) in an OData $batch changeset
*   3. WorkorderStatusChangeSet (POST)
*      -> API_MAINTENANCEORDER;v=2 / CE_API_MAINTENANCEORDER_0002:
*         ReleaseMaintenanceOrder, SetMaintOrdToTechCompleted,
*         CompleteMaintOrderBusiness, DoNotExecMaintenanceOrder
*   4. SparePlanSet (POST)
*      -> CE_PRODUCT_0002 (OData V4) / API_PRODUCT_SRV (SAP_COM_0009):
*         PATCH /ProductPlantSupplyPlanning('{Product}','{Plant}')
*         with ReorderThresholdQuantity & SafetyStockQuantity
*   5. ConfirmationCommentsSet (GET)
*      -> API_MAINTORDERCONFIRMATION:
*         GET /MaintOrderConfirmation?$filter=MaintenanceOrder eq '...'
*             &$expand=to_LongText
*   6. WorkorderoperationsSet (Single POST stub)
*      -> CE_API_MAINTENANCEORDER_0002: POST /MaintenanceOrderOperation
*   7. UserCheckSet (GET)
*      -> IPS_SCIM (SAP Cloud Identity SCIM 2.0): GET /Users
*
* STAGE 2 — On-Stack RAP Service (ZUI_PM_Details) Using 100% Released
*           Level A Objects Verified in SAP Cloudification Repository:
*   - DDLS (C1 Released):
*       I_Equipment, I_EquipmentText, I_EquipmentTimeSeg,
*       I_EquipmentBOMLink, I_BillOfMaterialItemBasic,
*       I_MaintenanceOrderDEX, I_MaintenanceOrderTP,
*       I_MaintenanceOrderOperationTP, I_MaintOrderOpLongTextTP,
*       I_MaintOrderConfirmationTP, I_StatusObjectStatusChange,
*       I_SystemStatusText, I_ReservationDocumentItem,
*       I_MaterialDocumentItem_2, I_MaterialStock_2,
*       I_Product, I_ProductDescription_2, I_ProductPlantBasic,
*       I_ProductPlantProcurement, I_ProductStorageLocationBasic,
*       I_Plant, I_PlantPurchasingOrganization,
*       I_Supplier, I_SupplierPurchasingOrg,
*       I_PurchaseOrderAPI01, I_PurchaseOrderItemAPI01,
*       I_PurOrdScheduleLineAPI01
*   - BDEF (C1 Released, for optional on-stack EML facade):
*       I_MaintenanceOrderTP, I_MaintOrderConfirmationTP, I_ProductTP_2
*   - INTF / CLAS (C1 Released):
*       IF_RAP_QUERY_PROVIDER, IF_RAP_QUERY_REQUEST,
*       IF_RAP_QUERY_RESPONSE, IF_RAP_QUERY_FILTER, IF_RAP_QUERY_PAGING,
*       CL_ABAP_CONTEXT_INFO, CX_RAP_QUERY_PROVIDER,
*       CX_RAP_QUERY_FILTER_NO_RANGE
*   - DTEL (C1 Released in Cloud & PCE):
*       EQUNR, WERKS_D, MATNR, AUFNR, BWART, LGORT_D, MEINS, EBELN,
*       EBELP, LIFNR, EKGRP, EKORG, RSNUM, RSPOS, MTART, MAKTX, KTEXT,
*       PLIFZ, LABST, BDMNG, ENMNG, MENGE_D, J_OBJNR, J_STATUS,
*       J_TXT04, BWTAR_D, WAERS, CO_RUECK, CO_RMZHL
*----------------------------------------------------------------------*


*======================================================================*
* 1. 3-Level Expanded Hierarchy (CDS View Entities with Associations)
*    Replaces: /IWBEP/IF_MGW_APPL_SRV_RUNTIME~GET_EXPANDED_ENTITYSET
*    Supports native OData V2/V4 $expand:
*      EquipmentHeaderSet?$expand=WorkOrderDetailsNav($expand=MaterialDetailsNav)
*    Fixes: Ignored $filter fields TechnicalId, EquipDescription, and
*           FunctionalLocation; replaces CHAR18 with 40-char MATNR.
*======================================================================*

*--- Level 3: Goods-Movement Material Details per Maintenance Order ---*
@AccessControl.authorizationCheck: #CHECK
@EndUserText.label: 'PM Order Goods Movement Material Details'
@Metadata.ignorePropagatedAnnotations: true
define view entity ZI_PM_MaterialDetails
  as select from I_MaterialDocumentItem_2 as MatDoc
    left outer to one join I_ProductDescription_2 as _ProdText
      on  MatDoc.Material   = _ProdText.Product
      and _ProdText.Language = $session.system_language
{
  key MatDoc.MaterialDocumentYear,
  key MatDoc.MaterialDocument,
  key MatDoc.MaterialDocumentItem,
      MatDoc.OrderID                as OrderId,
      MatDoc.Material               as MaterialId,
      _ProdText.ProductDescription  as MaterialDescription,
      MatDoc.Plant                  as Plant,
      MatDoc.StorageLocation        as StorageLocation,
      MatDoc.GoodsMovementType      as MovementType,
      MatDoc.PostingDate            as PostingDate,
      @Semantics.quantity.unitOfMeasure: 'BaseUnit'
      MatDoc.QuantityInBaseUnit     as Quantity,
      MatDoc.MaterialBaseUnit       as BaseUnit
}
where MatDoc.OrderID is not initial;


*--- Level 2: Maintenance Order Details per Equipment ---*
@AccessControl.authorizationCheck: #CHECK
@EndUserText.label: 'Equipment Maintenance Order Details'
@Metadata.ignorePropagatedAnnotations: true
define view entity ZI_PM_WorkOrderDetails
  as select from I_MaintenanceOrderDEX as MaintOrd
  association [0..*] to ZI_PM_MaterialDetails as _MaterialDetailsNav
    on $projection.OrderId = _MaterialDetailsNav.OrderId
{
  key MaintOrd.MaintenanceOrder         as OrderId,
      MaintOrd.Equipment                as EquipmentId,
      MaintOrd.MaintenanceOrderType     as OrderType,
      MaintOrd.MaintenanceOrderDesc     as OrderDescription,
      MaintOrd.MaintenancePlanningPlant as Plant,
      MaintOrd.MaintOrdBasicStartDate   as BasicStartDate,
      MaintOrd.MaintOrdBasicEndDate     as BasicEndDate,
      _MaterialDetailsNav               as MaterialDetailsNav
}
where MaintOrd.Equipment is not initial;


*--- Level 1: Equipment Header ---*
@AccessControl.authorizationCheck: #CHECK
@EndUserText.label: 'Equipment Header with Order & Material Expand'
@Metadata.ignorePropagatedAnnotations: true
define view entity ZI_PM_EquipmentHeader
  as select from I_Equipment as Equip
    left outer to one join I_EquipmentText as _EquipText
      on  Equip.Equipment     = _EquipText.Equipment
      and _EquipText.Language = $session.system_language
    left outer to one join I_EquipmentTimeSeg as _TimeSeg
      on  Equip.Equipment                        = _TimeSeg.Equipment
      and _TimeSeg.EquipUsagePeriodSequenceNumber = '001'
      and _TimeSeg.ValidityEndDate               >= $session.system_date
  association [0..*] to ZI_PM_WorkOrderDetails as _WorkOrderDetailsNav
    on $projection.EquipmentId = _WorkOrderDetailsNav.EquipmentId
{
  key Equip.Equipment                         as EquipmentId,
      Equip.Plant                             as Plant,
      Equip.TechnicalObjectNumber             as TechnicalId,
      _EquipText.EquipmentName                as EquipDescription,
      _TimeSeg.FunctionalLocation             as FunctionalLocation,
      _WorkOrderDetailsNav                    as WorkOrderDetailsNav
};


*======================================================================*
* 2. Equipment / Plant Material Lookup (ZI_PM_FLEQ_MAT_LOOKUP)
*    Replaces: FLEQMATERIALLOOK_GET_ENTITYSET (AFIH, AUFM, MAKT)
*    Fixes: Missing SPRAS filter on MAKT & procedural FOR ALL ENTRIES
*======================================================================*
@AccessControl.authorizationCheck: #CHECK
@EndUserText.label: 'Equipment Goods-Issued Material Lookup'
@Metadata.ignorePropagatedAnnotations: true
define view entity ZI_PM_FlEqMaterialLookup
  as select distinct from I_MaintenanceOrderDEX as MaintOrd
    inner join I_MaterialDocumentItem_2 as MatDoc
      on  MaintOrd.MaintenanceOrder         = MatDoc.OrderID
      and MaintOrd.MaintenancePlanningPlant = MatDoc.Plant
    left outer to one join I_ProductDescription_2 as _ProdText
      on  MatDoc.Material    = _ProdText.Product
      and _ProdText.Language = $session.system_language
{
  key MaintOrd.MaintenancePlanningPlant as Werks,
  key MaintOrd.Equipment                as Equnr,
  key MatDoc.Material                   as Matnr,
      _ProdText.ProductDescription      as Maktx
}
where MaintOrd.Equipment is not initial
  and MatDoc.Material    is not initial;


*======================================================================*
* 3. Equipment Spare Parts BOM Where-Used (ZI_PM_SPAREPARTS_BOM)
*    Replaces: SPAREPARTSBOMSET_GET_ENTITYSET (STPO, MARA, EQST, V_EQUI)
*    Fixes: Ignored Plant $filter (L1360) and SY-DATUM access
*======================================================================*
@AccessControl.authorizationCheck: #CHECK
@EndUserText.label: 'Spare Parts Equipment BOM Where-Used'
@Metadata.ignorePropagatedAnnotations: true
define view entity ZI_PM_SparePartsBOM
  as select distinct from I_BillOfMaterialItemBasic as BomItem
    inner join I_Product as Product
      on BomItem.BillOfMaterialComponent = Product.Product
    inner join I_EquipmentBOMLink as EqBom
      on  BomItem.BillOfMaterial         = EqBom.BillOfMaterial
      and BomItem.BillOfMaterialCategory = EqBom.BillOfMaterialCategory
    left outer to one join I_EquipmentTimeSeg as _TimeSeg
      on  EqBom.Equipment                         = _TimeSeg.Equipment
      and _TimeSeg.EquipUsagePeriodSequenceNumber = '001'
      and _TimeSeg.ValidityEndDate               >= $session.system_date
{
  key EqBom.Equipment                     as Equipment,
  key BomItem.BillOfMaterialComponent     as Material,
  key EqBom.Plant                         as Plant,
      Product.ProductType                 as MaterialType,
      _TimeSeg.FunctionalLocation         as FunctionalLoc
}
where BomItem.BillOfMaterialCategory = 'E';


*======================================================================*
* 4. Authorized Plant Lookup + DCL (ZI_PM_PLANT_LOOKUP)
*    Replaces: PLANTLOOKUPSET_GET_ENTITYSET (USR05 'WRK', T001W, ZPM_GET_USER_LANG)
*    Fixes: Drops USR05 colon-split hack and T001W-SPRAS filter bug
*           that hid plants with foreign communication languages
*======================================================================*
@AccessControl.authorizationCheck: #CHECK
@EndUserText.label: 'Authorized Plant Value Help'
@Metadata.ignorePropagatedAnnotations: true
define view entity ZI_PM_PlantLookup
  as select from I_Plant
{
  key Plant     as Plant,
      PlantName as Description
};

*--- Companion DCL Object (ZDCL_PM_PLANT_LOOKUP) ---*
@EndUserText.label: 'IAM Plant Authorization Inheritance'
@MappingRole: true
define role ZDCL_PM_PlantLookup {
  grant select on ZI_PM_PlantLookup
    where inherit I_Plant;
}


*======================================================================*
* 5. Vendor Code Lookup by Plant (ZI_PM_VENDOR_CODE_LOOKUP)
*    Replaces: VENDORCODELOOKUP_GET_ENTITYSET (T024W, LFM1, LFA1,
*              CRS_CREATE_WHERE_CONDITION dynamic SQL)
*    Fixes: Dynamic SQL injection/unreleased FM and LFA1-SPRAS filter bug
*======================================================================*
@AccessControl.authorizationCheck: #CHECK
@EndUserText.label: 'Supplier Lookup by Plant Purchasing Org'
@Metadata.ignorePropagatedAnnotations: true
define view entity ZI_PM_VendorCodeLookup
  as select distinct from I_PlantPurchasingOrganization as PlantPOrg
    inner join I_SupplierPurchasingOrg as SuppPOrg
      on PlantPOrg.PurchasingOrganization = SuppPOrg.PurchasingOrganization
    inner join I_Supplier as Supplier
      on SuppPOrg.Supplier = Supplier.Supplier
{
  key PlantPOrg.Plant                   as Werks,
  key Supplier.Supplier                 as Lifnr,
      PlantPOrg.PurchasingOrganization  as Ekorg,
      Supplier.SupplierFullName         as Name,
      Supplier.CityName                 as Ort01
}
where SuppPOrg.PurchasingIsBlocked = '';


*======================================================================*
* 6. Vendor Purchase Order & Open Schedule Search (ZI_PM_VENDOR_PO_SEARCH)
*    Replaces: VENDORPOSEARCHSE_GET_ENTITYSET (V_PUR_PO_ITM, EKET, LFA1)
*    Fixes: Forbidden SET LANGUAGE session leak (L2216), ignored
*           PurchGroup filter (L2093), and NetPrice vs NetAmount bug (L2188)
*======================================================================*
@AccessControl.authorizationCheck: #CHECK
@EndUserText.label: 'Vendor Purchase Order & Open Schedule Search'
@Metadata.ignorePropagatedAnnotations: true
define view entity ZI_PM_VendorPOSearch
  as select from I_PurchaseOrderItemAPI01 as POItem
    inner join I_PurchaseOrderAPI01 as POHeader
      on POItem.PurchaseOrder = POHeader.PurchaseOrder
    left outer to one join I_PurOrdScheduleLineAPI01 as _Sched
      on  POItem.PurchaseOrder     = _Sched.PurchaseOrder
      and POItem.PurchaseOrderItem = _Sched.PurchaseOrderItem
      and _Sched.ScheduleLine      = '0001'
    left outer to one join I_Supplier as _Supplier
      on POHeader.Supplier = _Supplier.Supplier
{
  key POItem.PurchaseOrder                                       as PoNum,
  key POItem.PurchaseOrderItem                                   as PoItem,
      POItem.Plant                                               as Plant,
      POItem.Material                                            as MaterialNum,
      POItem.PurchaseOrderItemText                               as ShortText,
      @Semantics.amount.currencyCode: 'DocumentCurrency'
      POItem.NetAmount                                           as TotalValue,
      @Semantics.amount.currencyCode: 'DocumentCurrency'
      POItem.NetPriceAmount                                      as UnitPrice,
      POHeader.DocumentCurrency                                  as DocumentCurrency,
      POHeader.PurchaseOrderDate                                 as DocDate,
      POHeader.PurchasingGroup                                   as PurchGroup,
      POHeader.Supplier                                          as Vendor,
      _Supplier.SupplierName                                     as Name,
      @Semantics.quantity.unitOfMeasure: 'OrderUnit'
      POItem.OrderQuantity                                       as OrderQty,
      POItem.PurchaseOrderQuantityUnit                           as OrderUnit,
      _Sched.ScheduleLineDeliveryDate                            as DeliveryDate,
      @Semantics.quantity.unitOfMeasure: 'OrderUnit'
      _Sched.ScheduleLineOrderQuantity - _Sched.RoughGoodsReceiptQty as OsQty,
      case
        when POItem.Material is not initial then 'Y'
        else 'N'
      end                                                        as SpareParts,
      case
        when POItem.IsCompletelyDelivered = '' then 'Y'
        else 'N'
      end                                                        as OsSpareParts
}
where POItem.PurchasingDocumentDeletionCode <> 'L'
  and POHeader.Supplier                     is not initial;


*======================================================================*
* 7. Fetch Report Configuration View (ZI_PM_FETCH_REPORT)
*    Replaces: FETCHREPORTSET_GET_ENTITYSET (ZPM_TECH_MAINT)
*    Fixes: Bug where SELECT executed INSIDE LOOP AT it_filter_select_options
*======================================================================*
@AccessControl.authorizationCheck: #NOT_REQUIRED
@EndUserText.label: 'PM Technical Report Configuration'
@Metadata.ignorePropagatedAnnotations: true
define view entity ZI_PM_FetchReport
  as select from zpm_tech_maint
{
  key value1 as Plant,
  key value2 as ReportName,
      param1 as Param1,
      param2 as Param2,
      param5 as Param5,
      value5 as ReportUrl
};


*======================================================================*
* 8. Custom Entities Backed by ABAP Cloud Query Providers
*======================================================================*

*--- 8A. Work Order Operations + Long Text + Release Date ---*
*    Replaces: WORKORDEROPERATI_GET_ENTITYSET
*    (BAPI_ALM_ORDER_GET_DETAIL, VIAUF_AFVC, READ_TEXT, WO_RELEASE_DATE)
@EndUserText.label: 'Maintenance Order Operations'
@ObjectModel.query.implementedBy: 'ABAP:ZCL_PM_WO_OPERATIONS_QP'
define custom entity ZI_PM_WorkOrderOperations
{
  key Aufnr              : aufnr;
  key Activity           : abap.char( 4 );
      SubActivity        : abap.char( 4 );
      ControlKey         : abap.char( 4 );
      WorkCntr           : abap.char( 8 );
      Plant              : werks_d;
      Description        : ktext;
      Lontext            : abap.string( 0 );
      @Semantics.quantity.unitOfMeasure: 'UnWork'
      Twork              : abap.quan( 7, 1 );
      UnWork             : meins;
      RelDate            : abap.dats;
      SystemStatusText   : j_txt04;
      ConfStart          : abap.char( 14 );
}


*--- 8B. Spare Plan 30-Day Rolling KPI Report ---*
*    Replaces: SPAREPLANREPORTS_GET_ENTITY (MATDOC, MARC, RESB)
*    Fixes: Critical CX_SY_ZERODIVIDE short dump (lv_nores TYPE n) & CHAR18
@EndUserText.label: 'Spare Parts 30-Day Demand & Lead Time Report'
@ObjectModel.query.implementedBy: 'ABAP:ZCL_PM_SPAREPLAN_RPT_QP'
define custom entity ZI_PM_SparePlanReport
{
  key Material         : matnr;
  key Plant            : werks_d;
      @Semantics.quantity.unitOfMeasure: 'BaseUnit'
      TotalReservedQty : menge_d;
      @Semantics.quantity.unitOfMeasure: 'BaseUnit'
      AvgDemandQty     : bdmng;
      BaseUnit         : meins;
      Criticality      : plifz;
}


*--- 8C. Reserved Spare Parts Workbench ---*
*    Replaces: RESERVEDSPAREPAR_GET_ENTITYSET (495 lines across VIAUFKS,
*              RESB, JEST, JSTO, TJ02T, TJ30T, MARD, MARC, MAKT, MSEG)
*    Fixes: Unassigned lv_materialid leaving stock_avail & bin blank,
*           and un-cleared ls_resb leaking IssueQty across rows
@EndUserText.label: 'Reserved Spare Parts Workbench'
@ObjectModel.query.implementedBy: 'ABAP:ZCL_PM_RESERVED_PARTS_QP'
define custom entity ZI_PM_ReservedSpareParts
{
  key Aufnr                     : aufnr;
  key Resno                     : rsnum;
  key ResItem                   : rspos;
      Matnr                     : matnr;
      Maktx                     : maktx;
      Plant                     : werks_d;
      StgeLoc                   : lgort_d;
      Bin                       : abap.char( 10 );
      Activity                  : abap.char( 4 );
      Equipment                 : equnr;
      WoDesc                    : ktext;
      OrderStatus               : abap.char( 40 );
      Bwtty                     : abap.char( 1 );
      Bdter                     : abap.dats;
      @Semantics.quantity.unitOfMeasure: 'RequirementQuantityUnit'
      RequirementQuantity       : bdmng;
      @Semantics.quantity.unitOfMeasure: 'RequirementQuantityUnit'
      WithdrawnQuantity         : enmng;
      @Semantics.quantity.unitOfMeasure: 'RequirementQuantityUnit'
      Enmng                     : enmng;
      @Semantics.quantity.unitOfMeasure: 'RequirementQuantityUnit'
      IssueQty                  : menge_d;
      @Semantics.quantity.unitOfMeasure: 'RequirementQuantityUnit'
      Labst                     : labst;
      @Semantics.quantity.unitOfMeasure: 'RequirementQuantityUnit'
      StockAvail                : labst;
      RequirementQuantityUnit   : meins;
}


*======================================================================*
* 9. RAP Service Definition (ZUI_PM_DETAILS)
*    Publish via Service Binding (SRVB) as OData V4 or OData V2 Web API/UI
*======================================================================*
@EndUserText.label: 'PM Details Clean Core Services'
define service ZUI_PM_Details {
  expose ZI_PM_EquipmentHeader      as EquipmentHeaderSet;
  expose ZI_PM_WorkOrderDetails     as WorkOrderDetailsSet;
  expose ZI_PM_MaterialDetails      as MaterialDetailsSet;
  expose ZI_PM_FlEqMaterialLookup   as FlEqMaterialLookupSet;
  expose ZI_PM_SparePartsBOM        as SparePartsBOMSet;
  expose ZI_PM_PlantLookup          as PlantLookupSet;
  expose ZI_PM_VendorCodeLookup     as VendorCodeLookupSet;
  expose ZI_PM_VendorPOSearch       as VendorPOSearchSet;
  expose ZI_PM_FetchReport          as FetchReportSet;
  expose ZI_PM_WorkOrderOperations  as WorkorderoperationsSet;
  expose ZI_PM_SparePlanReport      as SparePlanReportsSet;
  expose ZI_PM_ReservedSpareParts   as ReservedSparePartsSet;
}


*======================================================================*
* 10. Query Provider 1: ZCL_PM_WO_OPERATIONS_QP
*     Language Version: ABAP for Cloud Development (Clean Core Level A)
*======================================================================*
CLASS zcl_pm_wo_operations_qp DEFINITION
  PUBLIC
  FINAL
  CREATE PUBLIC.

  PUBLIC SECTION.
    INTERFACES if_rap_query_provider.

  PRIVATE SECTION.
    CONSTANTS gc_status_released TYPE j_status VALUE 'I0002'.

    TYPES tt_result TYPE STANDARD TABLE OF zi_pm_workorderoperations WITH EMPTY KEY.

    METHODS derive_priority_status
      IMPORTING
        it_active_codes  TYPE string_table
      RETURNING
        VALUE(rv_status) TYPE j_txt04.
ENDCLASS.



CLASS zcl_pm_wo_operations_qp IMPLEMENTATION.

  METHOD if_rap_query_provider~select.
    DATA lr_aufnr  TYPE RANGE OF aufnr.
    DATA lt_result TYPE tt_result.

    TRY.
        DATA(lt_filters) = io_request->get_filter( )->get_as_ranges( ).
      CATCH cx_rap_query_filter_no_range INTO DATA(lx_no_range).
        RAISE EXCEPTION TYPE cx_rap_query_provider
          EXPORTING
            previous = lx_no_range.
    ENDTRY.

    LOOP AT lt_filters INTO DATA(ls_filter).
      IF to_upper( ls_filter-name ) = 'AUFNR'.
        LOOP AT ls_filter-range INTO DATA(ls_rng).
          APPEND VALUE #(
            sign   = ls_rng-sign
            option = ls_rng-option
            low    = |{ ls_rng-low ALPHA = IN }|
            high   = COND #( WHEN ls_rng-high IS NOT INITIAL THEN |{ ls_rng-high ALPHA = IN }| )
          ) TO lr_aufnr.
        ENDLOOP.
      ENDIF.
    ENDLOOP.

    DATA(lv_offset)    = io_request->get_paging( )->get_offset( ).
    DATA(lv_page_size) = io_request->get_paging( )->get_page_size( ).
    DATA(lv_max_rows)  = COND i(
      WHEN lv_page_size = if_rap_query_paging=>page_size_unlimited THEN 0
      ELSE lv_page_size ).

    IF io_request->is_total_numb_of_rec_requested( ).
      SELECT COUNT( * )
        FROM I_MaintenanceOrderOperationTP
        WHERE MaintenanceOrder IN @lr_aufnr
        INTO @DATA(lv_count).
      io_response->set_total_number_of_records( lv_count ).
    ENDIF.

    IF NOT io_request->is_data_requested( ).
      RETURN.
    ENDIF.

    " 1. Read Operations + Order Object Number via Level A Released TP Views
    SELECT op~MaintenanceOrder                AS aufnr,
           op~MaintenanceOrderOperation       AS activity,
           op~MaintenanceOrderSubOperation    AS sub_activity,
           op~OperationControlKey             AS control_key,
           op~OperationWorkCenter             AS work_cntr,
           op~Plant                           AS plant,
           op~OperationDescription            AS description,
           op~OpActualWorkQuantity            AS work_actual,
           op~OpWorkQuantityUnit              AS work_unit,
           op~OpActualExecutionStartDate      AS act_start_date,
           op~OpActualExecutionStartTime      AS act_start_time,
           op~MaintOrderOperationInternalID   AS op_objnr,
           ord~MaintenanceOrderInternalID     AS ord_objnr
      FROM I_MaintenanceOrderOperationTP AS op
      INNER JOIN I_MaintenanceOrderTP AS ord
        ON op~MaintenanceOrder = ord~MaintenanceOrder
      WHERE op~MaintenanceOrder IN @lr_aufnr
      ORDER BY op~MaintenanceOrder, op~MaintenanceOrderOperation, op~MaintenanceOrderSubOperation
      INTO TABLE @DATA(lt_ops)
      OFFSET @lv_offset
      UP TO @lv_max_rows ROWS.

    IF lt_ops IS INITIAL.
      io_response->set_data( lt_result ).
      RETURN.
    ENDIF.

    DATA(lv_langu) = cl_abap_context_info=>get_system_language( ).

    " 2. Bulk-read Operation Long Texts (replaces READ_TEXT 'AVOT' inside LOOP!)
    SELECT MaintenanceOrder,
           MaintenanceOrderOperation,
           MaintenanceOrderSubOperation,
           PlainLongText
      FROM I_MaintOrderOpLongTextTP
      FOR ALL ENTRIES IN @lt_ops
      WHERE MaintenanceOrder             = @lt_ops-aufnr
        AND MaintenanceOrderOperation    = @lt_ops-activity
        AND MaintenanceOrderSubOperation = @lt_ops-sub_activity
        AND Language                     = @lv_langu
      INTO TABLE @DATA(lt_longtexts).

    SORT lt_longtexts BY MaintenanceOrder MaintenanceOrderOperation MaintenanceOrderSubOperation.

    " 3. Bulk-read Order Release Dates (I0002) from Released Status Change View
    "    Replaces ZCL_PM_WORKORDER=>WO_RELEASE_DATE (direct JCDS read)
    DATA lr_ord_objnr TYPE RANGE OF j_objnr.
    DATA lr_op_objnr  TYPE RANGE OF j_objnr.

    LOOP AT lt_ops INTO DATA(ls_op_key).
      IF ls_op_key-ord_objnr IS NOT INITIAL.
        APPEND VALUE #( sign = 'I' option = 'EQ' low = ls_op_key-ord_objnr ) TO lr_ord_objnr.
      ENDIF.
      IF ls_op_key-op_objnr IS NOT INITIAL.
        APPEND VALUE #( sign = 'I' option = 'EQ' low = ls_op_key-op_objnr ) TO lr_op_objnr.
      ENDIF.
    ENDLOOP.

    SORT lr_ord_objnr BY low.
    DELETE ADJACENT DUPLICATES FROM lr_ord_objnr COMPARING low.
    SORT lr_op_objnr BY low.
    DELETE ADJACENT DUPLICATES FROM lr_op_objnr COMPARING low.

    IF lr_ord_objnr IS NOT INITIAL.
      SELECT StatusObject,
             MIN( StatusChangeDate ) AS RelDate
        FROM I_StatusObjectStatusChange
        WHERE StatusObject            IN @lr_ord_objnr
          AND StatusCode              =  @gc_status_released
          AND StatusIsInactive        =  @abap_false
        GROUP BY StatusObject
        INTO TABLE @DATA(lt_rel_dates).
      SORT lt_rel_dates BY StatusObject.
    ENDIF.

    " 4. Bulk-read Active System Status Texts for Operations
    IF lr_op_objnr IS NOT INITIAL.
      SELECT DISTINCT chg~StatusObject,
                      txt~SystemStatusShortName
        FROM I_StatusObjectStatusChange AS chg
        INNER JOIN I_SystemStatusText AS txt
          ON  chg~StatusCode = txt~SystemStatus
          AND txt~Language   = 'E'
        WHERE chg~StatusObject     IN @lr_op_objnr
          AND chg~StatusIsInactive =  @abap_false
        INTO TABLE @DATA(lt_op_stat).
      SORT lt_op_stat BY StatusObject.
    ENDIF.

    " 5. Assemble output entities
    LOOP AT lt_ops INTO DATA(ls_op).
      DATA lv_lontext TYPE string.
      CLEAR lv_lontext.

      READ TABLE lt_longtexts INTO DATA(ls_ltxt)
        WITH KEY MaintenanceOrder             = ls_op-aufnr
                 MaintenanceOrderOperation    = ls_op-activity
                 MaintenanceOrderSubOperation = ls_op-sub_activity
        BINARY SEARCH.
      IF sy-subrc = 0 AND ls_ltxt-PlainLongText IS NOT INITIAL.
        lv_lontext = ls_ltxt-PlainLongText.
      ELSE.
        lv_lontext = ls_op-description.
      ENDIF.

      DATA lv_reldate TYPE d.
      CLEAR lv_reldate.
      READ TABLE lt_rel_dates INTO DATA(ls_rel)
        WITH KEY StatusObject = ls_op-ord_objnr BINARY SEARCH.
      IF sy-subrc = 0.
        lv_reldate = ls_rel-RelDate.
      ENDIF.

      DATA lt_codes TYPE string_table.
      CLEAR lt_codes.
      LOOP AT lt_op_stat INTO DATA(ls_stat) WHERE StatusObject = ls_op-op_objnr.
        APPEND CONV string( ls_stat-SystemStatusShortName ) TO lt_codes.
      ENDLOOP.

      APPEND VALUE #(
        aufnr            = ls_op-aufnr
        activity         = ls_op-activity
        subactivity      = ls_op-sub_activity
        controlkey       = ls_op-control_key
        workcntr         = ls_op-work_cntr
        plant            = ls_op-plant
        description      = ls_op-description
        lontext          = lv_lontext
        twork            = ls_op-work_actual
        unwork           = ls_op-work_unit
        reldate          = lv_reldate
        systemstatustext = derive_priority_status( lt_codes )
        confstart        = |{ ls_op-act_start_date }{ ls_op-act_start_time }|
      ) TO lt_result.
    ENDLOOP.

    io_response->set_data( lt_result ).
  ENDMETHOD.


  METHOD derive_priority_status.
    " Preserves exact status precedence from legacy L2375-L2393
    IF line_exists( it_active_codes[ table_line = 'TECO' ] ).
      rv_status = 'TECO'.
    ELSEIF line_exists( it_active_codes[ table_line = 'PCNF' ] ).
      rv_status = 'PCNF'.
    ELSEIF line_exists( it_active_codes[ table_line = 'CNF' ] ).
      rv_status = 'CNF'.
    ELSEIF line_exists( it_active_codes[ table_line = 'REL' ] ).
      rv_status = 'REL'.
    ELSEIF line_exists( it_active_codes[ table_line = 'CRTD' ] ).
      rv_status = 'CRTD'.
    ELSEIF line_exists( it_active_codes[ table_line = 'GMPS' ] ).
      rv_status = 'GMPS'.
    ELSEIF line_exists( it_active_codes[ table_line = 'MACM' ] ).
      rv_status = 'MACM'.
    ELSEIF line_exists( it_active_codes[ table_line = 'SETC' ] ).
      rv_status = 'SETC'.
    ENDIF.
  ENDMETHOD.

ENDCLASS.


*======================================================================*
* 11. Query Provider 2: ZCL_PM_SPAREPLAN_RPT_QP
*     Fixes CX_SY_ZERODIVIDE (lv_nores TYPE n) & CHAR18 S/4 truncation
*======================================================================*
CLASS zcl_pm_spareplan_rpt_qp DEFINITION
  PUBLIC
  FINAL
  CREATE PUBLIC.

  PUBLIC SECTION.
    INTERFACES if_rap_query_provider.
ENDCLASS.



CLASS zcl_pm_spareplan_rpt_qp IMPLEMENTATION.

  METHOD if_rap_query_provider~select.
    DATA lr_matnr  TYPE RANGE OF matnr.
    DATA lr_plant  TYPE RANGE OF werks_d.
    DATA lt_result TYPE STANDARD TABLE OF zi_pm_spareplanreport WITH EMPTY KEY.

    TRY.
        DATA(lt_filters) = io_request->get_filter( )->get_as_ranges( ).
      CATCH cx_rap_query_filter_no_range INTO DATA(lx_no_range).
        RAISE EXCEPTION TYPE cx_rap_query_provider
          EXPORTING
            previous = lx_no_range.
    ENDTRY.

    LOOP AT lt_filters INTO DATA(ls_filter).
      CASE to_upper( ls_filter-name ).
        WHEN 'MATERIAL'.
          LOOP AT ls_filter-range INTO DATA(ls_mat_rng).
            APPEND VALUE #(
              sign   = ls_mat_rng-sign
              option = ls_mat_rng-option
              low    = |{ ls_mat_rng-low ALPHA = IN }|
              high   = COND #( WHEN ls_mat_rng-high IS NOT INITIAL THEN |{ ls_mat_rng-high ALPHA = IN }| )
            ) TO lr_matnr.
          ENDLOOP.
        WHEN 'PLANT'.
          lr_plant = CORRESPONDING #( ls_filter-range ).
      ENDCASE.
    ENDLOOP.

    DATA(lv_offset)    = io_request->get_paging( )->get_offset( ).
    DATA(lv_page_size) = io_request->get_paging( )->get_page_size( ).
    DATA(lv_max_rows)  = COND i(
      WHEN lv_page_size = if_rap_query_paging=>page_size_unlimited THEN 0
      ELSE lv_page_size ).

    IF io_request->is_total_numb_of_rec_requested( ).
      SELECT COUNT( * )
        FROM I_ProductPlantProcurement
        WHERE Product IN @lr_matnr
          AND Plant   IN @lr_plant
        INTO @DATA(lv_total).
      io_response->set_total_number_of_records( lv_total ).
    ENDIF.

    IF NOT io_request->is_data_requested( ).
      RETURN.
    ENDIF.

    " 1. Read Plant Procurement Lead Time (PlannedDeliveryDurationInDays = MARC-PLIFZ)
    SELECT proc~Product                       AS material,
           proc~Plant                         AS plant,
           proc~PlannedDeliveryDurationInDays AS plifz,
           prod~BaseUnit                      AS base_unit
      FROM I_ProductPlantProcurement AS proc
      INNER JOIN I_Product AS prod
        ON proc~Product = prod~Product
      WHERE proc~Product IN @lr_matnr
        AND proc~Plant   IN @lr_plant
      ORDER BY proc~Product, proc~Plant
      INTO TABLE @DATA(lt_proc)
      OFFSET @lv_offset
      UP TO @lv_max_rows ROWS.

    IF lt_proc IS INITIAL.
      io_response->set_data( lt_result ).
      RETURN.
    ENDIF.

    DATA(lv_today)     = cl_abap_context_info=>get_system_date( ).
    DATA(lv_from_date) = lv_today - 30.

    " 2. Aggregate 30-day Goods Movement Qty directly in HANA via I_MaterialDocumentItem_2
    SELECT Material,
           Plant,
           SUM( QuantityInEntryUnit ) AS TotalMovementQty
      FROM I_MaterialDocumentItem_2
      FOR ALL ENTRIES IN @lt_proc
      WHERE Material    = @lt_proc-material
        AND Plant       = @lt_proc-plant
        AND PostingDate BETWEEN @lv_from_date AND @lv_today
      GROUP BY Material, Plant
      INTO TABLE @DATA(lt_matdoc_agg).

    SORT lt_matdoc_agg BY Material Plant.

    " 3. Aggregate 30-day Reservation Demand Qty & Count using TYPE INT8 (no TYPE n overflow!)
    SELECT Product,
           Plant,
           SUM( ResvnItmRequiredQtyInBaseUnit ) AS TotalReqQty,
           COUNT( * )                           AS ReservationCount
      FROM I_ReservationDocumentItem
      FOR ALL ENTRIES IN @lt_proc
      WHERE Product                  = @lt_proc-material
        AND Plant                    = @lt_proc-plant
        AND MatlCompRequirementDate  BETWEEN @lv_from_date AND @lv_today
        AND ReservationItmIsMarkedForDeltn = @abap_false
      GROUP BY Product, Plant
      INTO TABLE @DATA(lt_resb_agg).

    SORT lt_resb_agg BY Product Plant.

    LOOP AT lt_proc INTO DATA(ls_proc).
      DATA lv_tot_res TYPE menge_d VALUE 0.
      DATA lv_avg_req TYPE bdmng   VALUE 0.

      READ TABLE lt_matdoc_agg INTO DATA(ls_mdoc)
        WITH KEY Material = ls_proc-material
                 Plant    = ls_proc-plant
        BINARY SEARCH.
      IF sy-subrc = 0.
        lv_tot_res = ls_mdoc-TotalMovementQty.
      ENDIF.

      READ TABLE lt_resb_agg INTO DATA(ls_resb)
        WITH KEY Product = ls_proc-material
                 Plant   = ls_proc-plant
        BINARY SEARCH.
      IF sy-subrc = 0 AND ls_resb-ReservationCount > 0.
        lv_avg_req = ls_resb-TotalReqQty / ls_resb-ReservationCount.
      ENDIF.

      APPEND VALUE #(
        material         = ls_proc-material
        plant            = ls_proc-plant
        totalreservedqty = lv_tot_res
        avgdemandqty     = lv_avg_req
        baseunit         = ls_proc-base_unit
        criticality      = ls_proc-plifz
      ) TO lt_result.
    ENDLOOP.

    io_response->set_data( lt_result ).
  ENDMETHOD.

ENDCLASS.


*======================================================================*
* 12. Query Provider 3: ZCL_PM_RESERVED_PARTS_QP
*     Replaces 495-line RESERVEDSPAREPAR_GET_ENTITYSET in Clean Core
*     Fixes unassigned lv_materialid (stock_avail & bin) & leaked ls_resb
*======================================================================*
CLASS zcl_pm_reserved_parts_qp DEFINITION
  PUBLIC
  FINAL
  CREATE PUBLIC.

  PUBLIC SECTION.
    INTERFACES if_rap_query_provider.

  PRIVATE SECTION.
    CONSTANTS:
      gc_order_cat_pm TYPE c LENGTH 2 VALUE '30',
      gc_mvt_gi_order TYPE bwart      VALUE '261',
      gc_mvt_re_order TYPE bwart      VALUE '262',
      gc_credit       TYPE c LENGTH 1 VALUE 'H',
      gc_phase_compl  TYPE c LENGTH 2 VALUE '09'.
ENDCLASS.



CLASS zcl_pm_reserved_parts_qp IMPLEMENTATION.

  METHOD if_rap_query_provider~select.
    DATA lr_plant   TYPE RANGE OF werks_d.
    DATA lr_orderid TYPE RANGE OF aufnr.
    DATA lr_matnr   TYPE RANGE OF matnr.
    DATA lr_stgeloc TYPE RANGE OF lgort_d.
    DATA lr_bin     TYPE RANGE OF zi_pm_reservedspareparts-bin.
    DATA lt_result  TYPE STANDARD TABLE OF zi_pm_reservedspareparts WITH EMPTY KEY.

    TRY.
        DATA(lt_filters) = io_request->get_filter( )->get_as_ranges( ).
      CATCH cx_rap_query_filter_no_range INTO DATA(lx_no_range).
        RAISE EXCEPTION TYPE cx_rap_query_provider
          EXPORTING
            previous = lx_no_range.
    ENDTRY.

    LOOP AT lt_filters INTO DATA(ls_filter).
      CASE to_upper( ls_filter-name ).
        WHEN 'PLANT'.
          lr_plant = CORRESPONDING #( ls_filter-range ).
        WHEN 'AUFNR'.
          LOOP AT ls_filter-range INTO DATA(ls_ord_rng).
            APPEND VALUE #(
              sign   = ls_ord_rng-sign
              option = ls_ord_rng-option
              low    = |{ ls_ord_rng-low ALPHA = IN }|
              high   = COND #( WHEN ls_ord_rng-high IS NOT INITIAL THEN |{ ls_ord_rng-high ALPHA = IN }| )
            ) TO lr_orderid.
          ENDLOOP.
        WHEN 'MATNR'.
          LOOP AT ls_filter-range INTO DATA(ls_mat_rng).
            APPEND VALUE #(
              sign   = ls_mat_rng-sign
              option = ls_mat_rng-option
              low    = |{ ls_mat_rng-low ALPHA = IN }|
              high   = COND #( WHEN ls_mat_rng-high IS NOT INITIAL THEN |{ ls_mat_rng-high ALPHA = IN }| )
            ) TO lr_matnr.
          ENDLOOP.
        WHEN 'STGELOC'.
          lr_stgeloc = CORRESPONDING #( ls_filter-range ).
        WHEN 'BIN'.
          lr_bin = CORRESPONDING #( ls_filter-range ).
      ENDCASE.
    ENDLOOP.

    DATA(lv_today)     = cl_abap_context_info=>get_system_date( ).
    DATA(lv_date_from) = lv_today - 180.

    " 1. Select Open Maintenance Order Reservations via Level A CDS Views
    "    Replaces unreleased VIAUFKS + RESB + JEST exclusion (CRTD/TECO/CLSD)
    SELECT ord~MaintenanceOrder               AS aufnr,
           ord~MaintenanceOrderInternalID     AS objnr,
           ord~MaintenanceOrderDesc           AS ktext,
           ord~Equipment                      AS equnr,
           res~Reservation                    AS resno,
           res~ReservationItem                AS res_item,
           res~Product                        AS material,
           res~ManufacturingOrderOperation    AS activity,
           res~ResvnItmRequiredQtyInBaseUnit  AS requirement_quantity,
           res~BaseUnit                       AS requirement_quantity_unit,
           res~MatlCompRequirementDate        AS requirement_date,
           res~StorageLocation                AS stge_loc,
           res~Plant                          AS werks,
           res~ResvnItmWithdrawnQtyInBaseUnit AS withdrawn_quantity,
           sloc~WarehouseStorageBin           AS bin,
           plnt~ValuationCategory             AS bwtty
      FROM I_ReservationDocumentItem AS res
      INNER JOIN I_MaintenanceOrderTP AS ord
        ON res~OrderID = ord~MaintenanceOrder
      LEFT OUTER TO ONE JOIN I_ProductStorageLocationBasic AS sloc
        ON  res~Product         = sloc~Product
        AND res~Plant           = sloc~Plant
        AND res~StorageLocation = sloc~StorageLocation
      LEFT OUTER TO ONE JOIN I_ProductPlantBasic AS plnt
        ON  res~Product = plnt~Product
        AND res~Plant   = plnt~Plant
      WHERE ord~MaintenanceOrderCategory   =  @gc_order_cat_pm
        AND ord~MaintenanceProcessingPhase <> '00'
        AND ord~MaintenanceProcessingPhase <> @gc_phase_compl
        AND ord~MaintOrdBasicStartDate     BETWEEN @lv_date_from AND @lv_today
        AND res~Plant                      IN @lr_plant
        AND ord~MaintenanceOrder           IN @lr_orderid
        AND res~Product                    IN @lr_matnr
        AND res~StorageLocation            IN @lr_stgeloc
        AND sloc~WarehouseStorageBin       IN @lr_bin
        AND res~ReservationItmIsMarkedForDeltn = @abap_false
        AND res~ResvnItmRequiredQtyInBaseUnit  > 0
      ORDER BY ord~MaintenanceOrder DESCENDING, res~ReservationItem ASCENDING
      INTO TABLE @DATA(lt_wolist).

    IF io_request->is_total_numb_of_rec_requested( ).
      io_response->set_total_number_of_records( lines( lt_wolist ) ).
    ENDIF.

    IF NOT io_request->is_data_requested( ) OR lt_wolist IS INITIAL.
      io_response->set_data( lt_result ).
      RETURN.
    ENDIF.

    " 2. Apply RAP Paging ($skip / $top) cleanly before secondary enrichment
    DATA(lv_offset)    = io_request->get_paging( )->get_offset( ).
    DATA(lv_page_size) = io_request->get_paging( )->get_page_size( ).
    DATA(lv_start_idx) = lv_offset + 1.
    DATA(lv_end_idx)   = COND i(
      WHEN lv_page_size = if_rap_query_paging=>page_size_unlimited THEN lines( lt_wolist )
      ELSE nmin( val1 = lv_offset + lv_page_size val2 = lines( lt_wolist ) ) ).

    DATA lt_page LIKE lt_wolist.
    LOOP AT lt_wolist INTO DATA(ls_row) FROM lv_start_idx TO lv_end_idx.
      APPEND ls_row TO lt_page.
    ENDLOOP.

    IF lt_page IS INITIAL.
      io_response->set_data( lt_result ).
      RETURN.
    ENDIF.

    DATA(lv_langu) = cl_abap_context_info=>get_system_language( ).

    " 3. Product Descriptions via I_ProductDescription_2 (replaces unfiltered MAKT)
    SELECT Product,
           ProductDescription
      FROM I_ProductDescription_2
      FOR ALL ENTRIES IN @lt_page
      WHERE Product  = @lt_page-material
        AND Language = @lv_langu
      INTO TABLE @DATA(lt_makt).
    SORT lt_makt BY Product.

    " 4. Unrestricted Stock (InventoryStockType = '01') via I_MaterialStock_2
    "    Fixes critical bug where unassigned lv_materialid left stock_avail = 0!
    SELECT Material,
           Plant,
           StorageLocation,
           SUM( MatlWrhsStkQtyInMatlBaseUnit ) AS UnrestrictedQty
      FROM I_MaterialStock_2
      FOR ALL ENTRIES IN @lt_page
      WHERE Material           = @lt_page-material
        AND Plant              = @lt_page-werks
        AND InventoryStockType = '01'
      GROUP BY Material, Plant, StorageLocation
      INTO TABLE @DATA(lt_stock).
    SORT lt_stock BY Material Plant StorageLocation.

    " 5. Goods Issue Quantities (261/262) per Reservation Item via I_MaterialDocumentItem_2
    "    Fixes critical bug where un-cleared ls_resb leaked IssueQty across rows!
    SELECT Reservation,
           ReservationItem,
           DebitCreditCode,
           SUM( QuantityInBaseUnit ) AS IssuedQty
      FROM I_MaterialDocumentItem_2
      FOR ALL ENTRIES IN @lt_page
      WHERE Reservation       =  @lt_page-resno
        AND ReservationItem   =  @lt_page-res_item
        AND GoodsMovementType IN ( @gc_mvt_gi_order, @gc_mvt_re_order )
      GROUP BY Reservation, ReservationItem, DebitCreditCode
      INTO TABLE @DATA(lt_mseg).
    SORT lt_mseg BY Reservation ReservationItem DebitCreditCode.

    " 6. Assemble response rows
    LOOP AT lt_page INTO DATA(ls_woli).
      DATA lv_maktx       TYPE maktx   VALUE IS INITIAL.
      DATA lv_sloc_stock  TYPE labst   VALUE 0.
      DATA lv_plant_stock TYPE labst   VALUE 0.
      DATA lv_issue_qty   TYPE menge_d VALUE 0.

      CLEAR: lv_maktx, lv_sloc_stock, lv_plant_stock, lv_issue_qty.

      READ TABLE lt_makt INTO DATA(ls_maktx)
        WITH KEY Product = ls_woli-material BINARY SEARCH.
      IF sy-subrc = 0.
        lv_maktx = ls_maktx-ProductDescription.
      ENDIF.

      LOOP AT lt_stock INTO DATA(ls_stk)
        WHERE Material = ls_woli-material
          AND Plant    = ls_woli-werks.
        lv_plant_stock += ls_stk-UnrestrictedQty.
        IF ls_stk-StorageLocation = ls_woli-stge_loc.
          lv_sloc_stock += ls_stk-UnrestrictedQty.
        ENDIF.
      ENDLOOP.

      READ TABLE lt_mseg INTO DATA(ls_gi)
        WITH KEY Reservation     = ls_woli-resno
                 ReservationItem = ls_woli-res_item
                 DebitCreditCode = gc_credit
        BINARY SEARCH.
      IF sy-subrc = 0.
        lv_issue_qty = ls_gi-IssuedQty.
      ENDIF.

      DATA(lv_open_qty) = COND enmng(
        WHEN ls_woli-requirement_quantity > ls_woli-withdrawn_quantity
        THEN ls_woli-requirement_quantity - ls_woli-withdrawn_quantity
        ELSE 0 ).

      APPEND VALUE #(
        aufnr                   = ls_woli-aufnr
        resno                   = ls_woli-resno
        resitem                 = ls_woli-res_item
        matnr                   = ls_woli-material
        maktx                   = lv_maktx
        plant                   = ls_woli-werks
        stgeloc                 = ls_woli-stge_loc
        bin                     = ls_woli-bin
        activity                = ls_woli-activity
        equipment               = ls_woli-equnr
        wodesc                  = ls_woli-ktext
        bwtty                   = ls_woli-bwtty
        bdter                   = ls_woli-requirement_date
        requirementquantity     = ls_woli-requirement_quantity
        withdrawnquantity       = ls_woli-withdrawn_quantity
        enmng                   = lv_open_qty
        issueqty                = lv_issue_qty
        labst                   = lv_sloc_stock
        stockavail              = lv_plant_stock
        requirementquantityunit = ls_woli-requirement_quantity_unit
      ) TO lt_result.
    ENDLOOP.

    " 7. Dynamic $orderby support via released RAP Sort API
    DATA(lt_sort_elements) = io_request->get_sort_elements( ).
    IF lt_sort_elements IS NOT INITIAL.
      DATA lt_sort_order TYPE abap_sortorder_tab.
      LOOP AT lt_sort_elements INTO DATA(ls_sort).
        APPEND VALUE #(
          name       = to_upper( ls_sort-element_name )
          descending = ls_sort-descending
        ) TO lt_sort_order.
      ENDLOOP.
      SORT lt_result BY (lt_sort_order).
    ENDIF.

    io_response->set_data( lt_result ).
  ENDMETHOD.

ENDCLASS.


*======================================================================*
* 13. Optional On-Stack RAP EML Transactional Adapter
*     (If called from on-stack RAP Actions instead of API Hub OData)
*     Replaces: BAPI_MATERIAL_SAVEDATA, BAPI_ALM_ORDER_MAINTAIN, and
*               split-LUW BAPI_TRANSACTION_COMMIT calls!
*======================================================================*
CLASS zcl_pm_clean_core_actions DEFINITION
  PUBLIC
  FINAL
  CREATE PUBLIC.

  PUBLIC SECTION.
    METHODS update_spare_plan_mrp
      IMPORTING
        iv_product       TYPE matnr
        iv_plant         TYPE werks_d
        iv_reorder_point TYPE menge_d
        iv_safety_stock  TYPE menge_d
      EXPORTING
        ev_success       TYPE abap_bool.

    METHODS cancel_order_confirmation
      IMPORTING
        iv_conf_no       TYPE co_rueck
        iv_conf_counter  TYPE co_rmzhl
      EXPORTING
        ev_success       TYPE abap_bool.
ENDCLASS.



CLASS zcl_pm_clean_core_actions IMPLEMENTATION.

  METHOD update_spare_plan_mrp.
    " Clean Core Level A EML replacement for notToBeReleased BAPI_MATERIAL_SAVEDATA
    " NOTE: Inside a RAP Behavior Handler, NEVER call COMMIT ENTITIES; the RAP
    " framework commits the entire transactional buffer atomically in one LUW.
    DATA(lv_product) = |{ iv_product ALPHA = IN }|.

    MODIFY ENTITIES OF I_ProductTP_2
      ENTITY ProductPlantMRP
      UPDATE FIELDS ( ReorderThresholdQuantity SafetyStockQuantity )
      WITH VALUE #( (
        Product                  = lv_product
        MRPArea                  = iv_plant
        Plant                    = iv_plant
        ReorderThresholdQuantity = iv_reorder_point
        SafetyStockQuantity      = iv_safety_stock
      ) )
      FAILED DATA(ls_failed)
      REPORTED DATA(ls_reported).

    ev_success = xsdbool( ls_failed IS INITIAL ).
  ENDMETHOD.


  METHOD cancel_order_confirmation.
    " Clean Core Level A EML replacement for ZCL_PM_WORKORDER=>CANCEL_CONFIRMATION
    MODIFY ENTITIES OF I_MaintOrderConfirmationTP
      ENTITY MaintOrderConfirmation
      EXECUTE CancelMaintOrderConfirmation
      FROM VALUE #( (
        MaintOrderConf          = iv_conf_no
        MaintOrderConfCntrValue = iv_conf_counter
      ) )
      FAILED DATA(ls_failed)
      REPORTED DATA(ls_reported).

    ev_success = xsdbool( ls_failed IS INITIAL ).
  ENDMETHOD.

ENDCLASS.
