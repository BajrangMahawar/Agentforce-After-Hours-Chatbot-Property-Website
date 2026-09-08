/**
 * Files belong to whoever uploaded them. The Agentforce agent runs as its own
 * user, and ContentDocumentLink stays sharing-scoped even in a without-sharing
 * context, so a brochure uploaded by a sales user is invisible to the agent and
 * every document lookup comes back empty.
 *
 * Sharing each visitor-shareable file with the agent user closes that gap at the
 * moment the file is flagged, so nobody has to remember to do it by hand.
 */
public without sharing class ContentVersionShareHandler {
    private static final String LOG = 'DOC_SHARE';

    public static void shareWithAgentUser(List<ContentVersion> versions) {
        if (versions == null || versions.isEmpty()) {
            return;
        }

        Id agentUserId = agentUserId();
        if (agentUserId == null) {
            AgentforceLogger.log(LOG, 'SHARE', 'no agent user found, nothing shared');
            return;
        }

        Set<Id> documentIds = new Set<Id>();
        for (ContentVersion cv : versions) {
            if (cv.Shareable_With_Visitors__c == true && cv.ContentDocumentId != null) {
                documentIds.add(cv.ContentDocumentId);
            }
        }
        if (documentIds.isEmpty()) {
            return;
        }

        for (ContentDocumentLink existing : [
            SELECT ContentDocumentId FROM ContentDocumentLink
            WHERE ContentDocumentId IN :documentIds AND LinkedEntityId = :agentUserId
        ]) {
            documentIds.remove(existing.ContentDocumentId);
        }
        if (documentIds.isEmpty()) {
            return;
        }

        List<ContentDocumentLink> links = new List<ContentDocumentLink>();
        for (Id documentId : documentIds) {
            links.add(new ContentDocumentLink(
                ContentDocumentId = documentId,
                LinkedEntityId = agentUserId,
                ShareType = 'V',
                Visibility = 'AllUsers'
            ));
        }

        // A share that fails must not block the upload itself.
        Database.SaveResult[] results = Database.insert(links, false);
        Integer created = 0;
        for (Database.SaveResult result : results) {
            if (result.isSuccess()) {
                created++;
            } else {
                AgentforceLogger.log(LOG, 'SHARE', 'failed: ' + result.getErrors());
            }
        }
        AgentforceLogger.log(LOG, 'SHARE', 'shared ' + created + ' of ' + links.size() +
            ' document(s) with the agent user');
    }

    /** The agent user is the one the bot posts as; it owns no files of its own. */
    private static Id agentUserId() {
        List<User> matches = [
            SELECT Id FROM User
            WHERE Username LIKE 'agentforce_after_hours_chatbot_for_property_website@%'
              AND IsActive = true
            LIMIT 1
        ];
        return matches.isEmpty() ? null : matches[0].Id;
    }
}
