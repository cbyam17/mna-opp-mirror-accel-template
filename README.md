# M&A Opportunity Mirroring Accelerator Template

This is an accelerator template for an integration solution that mirrors Opportunities and Opportunity Line Items (OLIs) from a source Salesforce CRM instance to a target Salesforce CRM instance to support revenue forecasting during M&A interim operations. The purpose of this template is to reduce the time to deliver an Opportunity mirroring integration solution while minimizing the configuration changes required on both the source and the target Salesforce CRM instances.

## Process Overview

There are 3 main flows that fetch Opportunities and OLIs in scope for mirroring from the source Salesforce instance, write them to the target Salesforce instance, and write the Opportunity Ids back to the source Salesforce instance.
| Flow              | Event Source      | Description |
|-------------    |--------------   |-------------- |
| Main Scheduler    | Scheduler         | Regularly scheduled job that processes records from the source Salesforce instance based on the watermark lastRunDateTime value |
| Retry Scheduler   | Scheduler         | Regularly scheduled job that fetches failed records from the error hospital and attempts to reprocess them a configurable number of times |
| Admin Reprocess   | HTTP Request      | HTTP endpoint that supports ad hoc reprocessing of records by Id |

The process can be broken down into 4 phases. The watermark service is only used by the main scheduler flow — both the retry scheduler and admin reprocess flows use record Ids to fetch Opportunities from the source Salesforce instance, sourced from the error hospital and HTTP request body.

1. Preprocessing

    - Retrieve watermark lastRunDateTime from a persistent Object Store
    - Fetch Opportunities and OLIs from the source Salesforce instance
    - Fetch existing Opportunities, OLIs, and Accounts from the target Salesforce instance
    - Fetch matching error hospital records
    - Enrich payload with aggregated data
    - Store batchStatus as IN_PROGRESS in a transient Object Store

2. Batch processing

    - Upsert Opportunities and OLIs in the target Salesforce instance
    - Delete OLIs in the target Salesforce instance (if required)
    - Writeback target Opportunity Ids and/or error details to the source Salesforce instance
    - Write failed records to the error hospital
    - Remove previously failed but successful records from the error hospital

3. Postprocessing

    - Clear batchStatus in transient Object Store
    - Store watermark in persistent Object Store
    - Send summary email if failedRecords > 0
    - Send notification if error hospital write errors exist

**Note:** Error hospital write failures are caught and written to a failureBuffer transient Object Store for batch-on-complete handling.

## Prerequisites

### MuleSoft Platform

- CloudHub or CloudHub 2.0
- Object Store v2 (Persistent and Transient)
- Java 17
- Mule runtime 4.11.0

**Note on Mule Runtime Compatibility:** Mule runtime 4.11.0 introduced improved batch processing error‑handling and also resolved a known Java 17–related serialization issue that affects exceptions thrown by the Salesforce connector during batch execution.
You can run this template on earlier Mule runtimes; however, if you do, you may need to adjust certain error‑handling paths—specifically those that manage exceptions raised inside batch jobs—because older runtimes do not include the fixes provided in 4.11.0.

### Salesforce Source Instance

Fields required on **Opportunity**:

| Field                           | Type            | Description |
|---------------------------------|-----------------|-------------|
| Is_In_Mirror_Scope_TGT__c       | Boolean         | Determines if Opportunity is in scope to mirror to target Salesforce instance |
| Ready_To_Mirror_DateTime_TGT__c | DateTime        | Timestamp that Opportunity is ready to mirror |
| Opp_Id_TGT__c                   | Text (18 chars) | Target Opportunity Id (for writeback) |
| Mirror_Error_TGT__c             | Text (255 chars)| Error details captured during mirror process (for writeback) |

Fields required on **Account**:

| Field          | Type            | Description |
|----------------|-----------------|-------------|
| Acct_Id_TGT__c | Text (18 chars) | Target Account Id |

### Salesforce Target Instance

Fields required on **Opportunity**:

| Field        | Type            | Description |
|--------------|-----------------|-------------|
| Opp_Id_SRC__c| Text (18 chars) | Source Opportunity Id |

Fields required on **Opportunity Line Item**:

| Field        | Type            | Description |
|--------------|-----------------|-------------|
| Oli_Id_SRC__c| Text (18 chars) | Source OLI Id |

## Data Dependencies

- Products and Pricebook Entries corresponding to the source Product offerings must be preloaded into the target Salesforce instance.
- Accounts must be mapped from the target Salesforce instance to the source Salesforce instance either manually or via a separate integration.

## Mule Implementation Files (src/main/mule)

| File               | Description |
|--------------------|-------------|
| admin.xml          | Admin reprocess implementation |
| api.xml            | API implementation |
| batch.xml          | Batch processing implementation |
| email.xml          | Email implementation |
| error.xml          | Error handling implementation |
| error-hospital.xml | Error hospital implementation (could be replaced by an external service) |
| global.xml         | Global configurations |
| health-check.xml   | Health check implementation |
| os.xml             | ObjectStore v2 implementation |
| process.xml        | Process orchestration implementation |
| scheduler.xml      | Scheduler flows implementation |
| source.xml         | Source Salesforce implementation |
| target.xml         | Target Salesforce implementation |
| watermark.xml      | Watermark implementation (could be replaced by an external service) |

## DataWeave Modules (src/main/resources/module)

| Module                  | Description |
|-------------------------|-------------|
| Account.dwl             | Account transformations |
| Opportunity.dwl         | Opportunity transformations |
| OpportunityLineItem.dwl | OLI transformations |
| PricebookEntry.dwl      | Pricebook Entry transformations |
| ErrorHospital.dwl       | Error hospital transformations |
| CommonUtils.dwl         | Reusable utilities |

## Configuration Properties (src/main/resources/config)

Runtime arguments: mule.env, mule.key
- dev.yaml
- dev-secure.yaml
- qa.yaml
- qa-secure.yaml
- uat.yaml
- uat-secure.yaml
- prod.yaml
- prod-secure.yaml

## API (src/main/resources/api)

File: mna-opp-mirror-accel-template-api.raml

| Endpoint                  | Description |
|---------------------------|-------------|
| POST /api/admin/reprocess | Ad hoc reprocessing of Opportunities |
| PUT /api/admin/watermark  | Update watermark timestamp |
| GET /api/health-check     | Perform dependency health check |

## Email Templates (src/main/resources/email)

| Template                            | Description |
|-------------------------------------|-------------|
| batchPostprocessErrorTemplate.html  | Postprocessing error notification |
| batchPreprocessErrorTemplate.html   | Preprocessing error notification |
| batchSummaryErrorTemplate.html      | Summary error notification |
| errorHospitalWriteErrorTemplate.html| Error hospital write error notification |
| healthCheckErrorTemplate.html       | Health check error notification |

## Error Handling (src/main/mule/error.xml)

| Error Handler                    | Description |
|----------------------------------|-------------|
| apiErrorHandler                  | Handle exceptions encountered in API implementation |
| batchPostprocessingErrorHandler  | Handle exceptions encountered in batch on-complete phase |
| batchPreprocessingErrorHandler   | Handle exceptions encountered in batch pre-processing phase |
| errorHospitalWriteErrorHandler   | Handle exceptions encountered writing to the error hospital|
| healthCheckErrorHandler          | Handle exceptions encountered during the health check|
| sendEmailErrorHandler            | Handle exceptions encountered sending emails |

## Considerations

- Externalizing configuration properties via CPS is recommended for production.
- Consider replacing persistent ObjectStore-based services (watermark and error hospital) with durable external services.
- Mule runtimes before 4.11.0 may experience batch serialization issues.
