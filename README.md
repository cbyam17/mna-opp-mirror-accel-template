# mna-oppty-mirror-accel-template
This is an accelerator template for an integration solution that mirrors Opportunities and Opportunity Line Items (OLIs) from a source Salesforce CRM instance to a target Salesforce CRM instance to support revenue forecasting during M&A interim operations. The purpose of this template is to reduce the time to deliver an Opportunity mirroring integration solution while minimizing the configuration changes required on both the source and the target Salesforce CRM instances.

## Process Overview
There are 3 main flows that fetch Opportunities and OLIs that are in scope to mirror from the source Salesforce instance, write them to the target Salesforce instance, and write the Opportunity Id back to the source Salesforce instance.
| Flow              | Event Source      | Description
| :-------------    | :--------------   | :--------------
| Main Scheduler    | Scheduler         | Regularly scheduled job that processes records from the source Salesforce instance based on the watermark lastRunDateTime value |
| Retry Scheduler   | Scheduler         | Regularly scheduled job that fetches failed records from the error hospital and attempts to reprocess them a configurable number of times |
| Admin Reprocess   | HTTP Request      | HTTP endpoint that supports ad hoc reprocessing of records |

The process can be broken down into 4 phases. The watermark service is only used by the main scheduler flow — both the retry scheduler and admin reprocess flows use record Ids to fetch Opportunities from the source Salesforce instance, which are sourced from the error hospital and HTTP request body, respectively.
1. Preprocessing
    - Retrieve watermark lastRunDateTime from a persistent Object Store
    - Fetch Opportunities and OLIs from the source Salesforce instance
    - Fetch existing Opportunities, OLIs, and Accounts from the target Salesforce instance
    - Fetch matching error hospital records
    - Enrich payload with the aggregated data
    - Store batchStatus as IN_PROGRESS in a transient Object Store
2. Batch processing
    - Upsert Opportunities and OLIs in the target Salesforce instance
    - Delete OLIs in the target Salesforce instance (if required)
    - Writeback target Salesforce instance Opportunity Ids and/or mirroring error details to the source Salesforce instance
    - Publish failed records to an AnypointMQ queue to insert into the error hospital
    - Publish successful previously failed records to an AnypointMQ queue to remove from the error hospital
3. Postprocessing
    - Clear batchStatus in a transient Object Store
    - Store watermark lastRunDateTime in a persistent Object Store
    - Send summary email if failedRecords > 0
4. Error Hospital Writes
    - Consume messages from an AnypointMQ queue and store records in a persistent Object Store (error hospital)
    - Consume messages from an AnypointMQ queue and remove records from a persistent Object Store (error hospital)

**Note**: To improve batch job performance and avoid noise from non‑critical errors, error hospital writes are decoupled from the core processing logic using AnypointMQ queues.

## Prerequisites
### MuleSoft Platform
- CloudHub or CloudHub 2.0
- Java 17
- Mule runtime 4.11.0 ([includes enhanced batch error handling](https://docs.mulesoft.com/release-notes/mule-runtime/mule-4.11.0-release-notes))
- AnypointMQ
    - Queue for inserting records into the error hospital 
    - Queue for removing records from the error hospital

**Note**: VM queues provide a viable fallback when Anypoint MQ is not an option, though they lack message persistence and will not survive application restarts or crashes.

### Salesforce Source Instance
There must be the following fields on the **Opportunity** object:
| Field                             | Type             | Description |
| :-------------                    | :--------------  | :-------------- |
| Is_In_Mirror_Scope_TGT__c         | Boolean          | Determines if Opportunity is in scope to mirror to the target Salesforce instance |
| Ready_To_Mirror_Datetime_TGT__c   | Datetime         | Datetime that an Opportunity is ready to mirror to the target Salesforce instance |
| Opp_Id_TGT__c                     | Text (16 chars)  | Id of the target Salesforce instance Opportunity |
| Mirror_Error_TGT__c               | Text (255 chars) | Details of errors encountered during the mirror process |

**Note**: This template does NOT write the target Salesforce instance OLI Ids back to the source Salesforce instance OLIs. If this functionality is required, an extra batch step would need to be configured to do so.

There must be the following field on the **Account** object:
| Field             | Type             | Description |
| :-------------    | :--------------  | :-------------- |
| Acct_Id_TGT__c    | Text (16 chars)  | Id of the target Salesforce instance Account |

### Salesforce Target Instance
There must be the following field on the **Opportunity** object:
| Field             | Type              | Description |
| :-------------    | :--------------   | :-------------- |
| Opp_Id_SRC__c     | Text (16 chars)             | Id of the source Salesforce instance Opportunity

There must be the following field on the **OLI** object:
| Field             | Type              | Description |
| :-------------    | :--------------   | :-------------- |
| Oli_Id_SRC__c     | Text (16 chars)   | Id of the source Salesforce instance OLI

**Note**: Neither of these fields need to be enabled as an external Ids, but they are required for fetching existing Opportunities and OLIs in the target Salesforce instance during batch preprocessing. If these fields can be enabled as external Ids, the template can be modified to:
1. Remove the preprocessing step of fetching existing Opportunities in the target Salesforce instance — fetching existing OLIs is still required to conditionally identify OLIs to delete
2. Perform upserts based on these external Ids rather than the native Salesforce Opportunity and OLI Ids

### Data Dependencies
Products and Pricebook Entries for source Salesforce instance Products must be pre-loaded into the target Salesforce instance. Only the Pricebook Entry Id is required for upserting OLIs. The mappings between the source Salesforce instance Pricebook Entries and target Salesforce instance Pricebook Entries for each Product are maintained in the configuration properties so that they are decoupled from the application logic.

Accounts must be migrated.....[tbd]

## What is included in this template?
### Mule Implementation Files (src/main/mule)
| File              | Description |
| :-------------    | :--------------
| admin.xml         | Admin reprocess implementation |
| amq.xml           | AnypointMQ implementation |
| api.xml           | API implementation |
| batch.xml         | Batch process implementation|
| email.xml         | Email implementation |
| error.xml         | Error handling implementation |
| error-hospital.xml| Error hospital implementation |
| global.xml        | Global configurations |
| health-check.xml  | Endpoints health check implementation |
| os.xml            | ObjectStore v2 implementation |
| process.xml       | Process logic implementation |
| scheduler.xml     | Main and retry scheduler implementation |
| source.xml        | Source Salesforce implementation |
| target.xml        | Target Salesforce implementation |
| watermark.xml     | Watermark implementation |

### Dataweave Modules (src/main/resources/module)
| Module                    | Description |
| :-------------            | :--------------
| Account.dwl               | Salesforce Account dataweave transformations |
| Opportunity.dwl           | Salesforce Opportunity dataweave transformations |
| OpportunityLineItem.dwl   | Salesforce OLI dataweave transformations |
| PricebookEntry.dwl        | Salesforce Pricebook Entry dataweave transformations |
| ErrorHospital.dwl         | Error hospital dataweave transformations |
| CommonUtils.dwl           | Reusable dataweave transformations |

### Configuration Properties (src/main/resources/config)
Runtime arguments: mule.env and mule.key
- dev.yaml
- dev-secure.yaml
- qa.yaml
- qa-secure.yaml
- uat.yaml
- uat-secure.yaml
- prod.yaml
- prod-secure.yaml

### API (src/main/resource/api)
RAML spec for admin reprocess endpoint
- mna-oppty-mirror-accel-template-api.raml

### Email Templates (src/main/resources/email)
| Template                              | Description |
| :-------------                        | :--------------
| batchPostprocessErrorTemplate.html    | Email template for batch postprocessing error notifications |
| batchPreprocessErrorTemplate.html     | Email template for batch preprocessing error notifications |
| batchSummaryErrorTemplate.html        | Email template for batch summary error notifications |
| errorHospitalWriteErrorTemplate.html  | Email template for error hospital write error notifications |
| healthCheckErrorTemplate.html         | Email template for health check error notifications |

## Considerations
The configuration properties are located in the /config folder, but it may be desirable in a production-ready solution to utilize a CPS service so that properties are decoupled from source code.

The error hospital and watermark services are implemented as persistent Object Stores within the application, but it may be desirable in a production-ready solution to replace them with more durable external services (i.e. a database) to decouple these services from the application itself.

There are some known issues in Mule runtimes prior to 4.11.0 and Java 17 with serializing errors thrown during batch processing, particularly by the Salesforce connector, which causes unexpected behavior. If Mule runtime 4.11.0 or later is not an option, some additional measures will need to be taken for error handling within the batch job:
- Wrap each Salesforce operation in a try/catch block with an error handler that extracts error type and error message and rethrows a custom error (i.e. APP:SALESFORCE_ERROR) with a description containing the original error type and error message structured as a JSON object
- Replace Batch::getLastError() with Batch::getLastException() and update any downstream variable assignments since they have different response structures (more info [here](https://docs.mulesoft.com/mule-runtime/latest/batch-error-handling-faq))

For more information on serialization errors and upgrading from Java 8/11 to Java 17, see below:
- [How to diagnose com.esotericsoftware.kryo related exceptions in batch](https://help.salesforce.com/s/articleView?id=001118572&type=1)
- [MuleSoft Java 17 Upgrade: Fixes for the Most Common Compatibility Errors](https://medium.com/@dileepkonari50/common-errors-while-upgrading-to-java-17-in-mule-724bfdfed0a2)
- [Upgrading MuleSoft to Java 17: A Comprehensive Guide](https://help.salesforce.com/s/articleView?id=002139151&type=1)