/**
 * Calls Get Property Detail exactly the way Agentforce calls it, so the whole
 * action can be exercised without going through the agent.
 *
 * Change PROPERTY_NAME (or set PROPERTY_ID) to the project you want to inspect.
 * Everything the action logs goes out under the SITEVISIT tag, so the debug log
 * shows the same trail the agent would produce.
 *
 *   sf apex run --file scripts/apex/run-property-detail.apex --target-org vscodeOrg
 */

final String PROPERTY_NAME = 'DLF Capital Greens';   // partial names are matched
final String PROPERTY_ID   = null;        // set this to skip name matching entirely

AgentforcePropertyDetailController.PropertyDetailRequest req =
    new AgentforcePropertyDetailController.PropertyDetailRequest();
req.propertyName = PROPERTY_NAME;
req.propertyId   = PROPERTY_ID;

List<AgentforcePropertyDetailController.PropertyDetailResult> results =
    AgentforcePropertyDetailController.getPropertyDetail(
        new List<AgentforcePropertyDetailController.PropertyDetailRequest>{ req }
    );

// ---------------------------------------------------------------- what came back
for (AgentforcePropertyDetailController.PropertyDetailResult res : results) {
    System.debug(LoggingLevel.INFO, '=== RESULT ===');
    System.debug(LoggingLevel.INFO, 'isSuccess=' + res.isSuccess + ' isFound=' + res.isFound);
    System.debug(LoggingLevel.INFO, 'message=' + res.message);
    System.debug(LoggingLevel.INFO, 'propertyId=' + res.propertyId + ' name=' + res.name);
    System.debug(LoggingLevel.INFO, 'city=' + res.city + ' status=' + res.status +
        ' priceRange=' + res.priceRange);
    System.debug(LoggingLevel.INFO, 'specifications=' + res.specificationCount +
        ' mediators=' + res.mediatorCount + ' documents=' + res.documentCount);

    // The flat string the agent actually reads, printed line by line so long
    // public URLs are not truncated by the log viewer.
    System.debug(LoggingLevel.INFO, '=== documentLinks ===');
    if (res.documentLinks == null) {
        System.debug(LoggingLevel.INFO, '<null> - class may not be deployed with this field yet');
    } else {
        for (String line : res.documentLinks.split('\n')) {
            System.debug(LoggingLevel.INFO, line);
        }
    }

    System.debug(LoggingLevel.INFO, '=== documents (nested) ===');
    for (AgentforcePropertyDetailController.DocumentInfo doc : res.documents) {
        System.debug(LoggingLevel.INFO, doc.documentType + ' | ' + doc.title +
            ' | ' + AgentforceLogger.show(doc.downloadUrl));
    }
}
