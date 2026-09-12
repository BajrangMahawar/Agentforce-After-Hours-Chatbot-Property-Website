/**
 * Covers the two things the chat window depends on and nothing else does:
 * that a card arrives with its hero image already resolved to a public URL,
 * and that a non-image file lands in `documents` rather than in the gallery.
 */
@isTest
private class PropertyChatControllerTest {
    private static Property__c tower;
    private static Property__c annexe;

    private static void makeProperties() {
        tower = new Property__c(
            Name = 'Chat Test Tower',
            City__c = 'Gurugram',
            Status__c = 'Ready to Move',
            Configurations__c = '3 BHK',
            Price_Min__c = 12000000,
            Price_Max__c = 18000000,
            Possession_Date__c = Date.today().addDays(-30)
        );
        annexe = new Property__c(
            Name = 'Chat Test Annexe',
            City__c = 'Noida',
            Status__c = 'Under Construction',
            Configurations__c = '2 BHK',
            Price_Min__c = 6000000,
            Price_Max__c = 8000000,
            Possession_Date__c = Date.today().addYears(2)
        );
        insert new List<Property__c>{ tower, annexe };
    }

    /** Links one file to a property and returns its ContentVersion Id. */
    private static Id attachFile(Id propertyId, String title, String extension, Boolean shareable) {
        return attachFile(propertyId, title, extension, shareable, 'Image / Gallery');
    }

    private static Id attachFile(
        Id propertyId, String title, String extension, Boolean shareable, String documentType
    ) {
        ContentVersion cv = new ContentVersion(
            Title = title,
            PathOnClient = title + '.' + extension,
            VersionData = Blob.valueOf('file body for ' + title),
            Document_Type__c = documentType,
            Shareable_With_Visitors__c = shareable
        );
        insert cv;

        Id documentId = [SELECT ContentDocumentId FROM ContentVersion WHERE Id = :cv.Id].ContentDocumentId;
        insert new ContentDocumentLink(
            ContentDocumentId = documentId,
            LinkedEntityId = propertyId,
            ShareType = 'V',
            Visibility = 'AllUsers'
        );
        return cv.Id;
    }

    @isTest
    static void searchReturnsHeroImageForAShareableImageFile() {
        makeProperties();
        attachFile(tower.Id, 'Tower Facade', 'jpg', true);

        Test.startTest();
        List<PropertyChatController.PropertyCard> cards =
            PropertyChatController.searchProperties('Gurugram', null, null, null, null);
        Test.stopTest();

        Assert.areEqual(1, cards.size(), 'Only the Gurugram property should match');
        PropertyChatController.PropertyCard card = cards[0];
        Assert.areEqual('Chat Test Tower', card.name);
        Assert.areEqual(1, card.imageCount, 'The one shareable image should be counted');
        Assert.isNotNull(card.heroImageUrl, 'A shareable image must resolve to a public URL');
        Assert.areEqual('Ready to move', card.possession,
            'A possession date in the past reads as ready to move');
    }

    @isTest
    static void nonShareableFilesNeverReachACard() {
        makeProperties();
        attachFile(tower.Id, 'Internal Costing', 'png', false);

        Test.startTest();
        List<PropertyChatController.PropertyCard> cards =
            PropertyChatController.searchProperties('Gurugram', null, null, null, null);
        Test.stopTest();

        Assert.areEqual(0, cards[0].imageCount, 'A file not marked shareable must stay out of the gallery');
        Assert.isNull(cards[0].heroImageUrl);
        Assert.areEqual('CT', cards[0].initials, 'Without an image the card falls back to a monogram');
    }

    @isTest
    static void detailSplitsImagesFromDocuments() {
        makeProperties();
        attachFile(tower.Id, 'Tower Facade', 'jpg', true);
        attachFile(tower.Id, 'Tower Brochure', 'pdf', true, 'Brochure');

        Test.startTest();
        PropertyChatController.PropertyDetail detail =
            PropertyChatController.getPropertyDetail(tower.Id);
        Test.stopTest();

        Assert.isNotNull(detail, 'A live property Id must resolve');
        Assert.areEqual(1, detail.images.size(), 'Only the gallery jpg belongs in the gallery');
        Assert.isTrue(detail.images[0].isGallery);
        Assert.areEqual(1, detail.documents.size(), 'Only the pdf belongs in the document list');
        Assert.isFalse(detail.documents[0].isImage);
        Assert.areEqual('Tower Brochure', detail.documents[0].title);
    }

    /**
     * A brochure is routinely uploaded as a jpg of its cover page. The
     * extension would make it the hero photograph, so the Document Type has
     * to win - the visitor must see the building, not a cover sheet.
     */
    @isTest
    static void aBrochureUploadedAsAnImageStaysOutOfTheGallery() {
        makeProperties();
        attachFile(tower.Id, 'Tower Brochure Cover', 'jpg', true, 'Brochure');
        attachFile(tower.Id, 'Tower Facade', 'jpg', true, 'Image / Gallery');

        Test.startTest();
        PropertyChatController.PropertyDetail detail =
            PropertyChatController.getPropertyDetail(tower.Id);
        List<PropertyChatController.PropertyCard> cards =
            PropertyChatController.searchProperties(null, null, null, null, 'Tower');
        Test.stopTest();

        Assert.areEqual(1, detail.images.size(), 'Only the Image / Gallery file is photography');
        Assert.areEqual('Tower Facade', detail.images[0].title, 'The facade must be the hero');
        Assert.areEqual(1, detail.documents.size(), 'The jpg brochure belongs with the documents');
        Assert.areEqual('Tower Brochure Cover', detail.documents[0].title);
        Assert.isTrue(detail.documents[0].isImage, 'It is still an image file...');
        Assert.isFalse(detail.documents[0].isGallery, '...but it is not project photography');
        Assert.areEqual(1, cards[0].imageCount, 'The card counts only gallery photography');
    }

    @isTest
    static void detailResolvesByPartialName() {
        makeProperties();

        Test.startTest();
        PropertyChatController.PropertyDetail byName =
            PropertyChatController.getPropertyDetail('Test Annexe');
        PropertyChatController.PropertyDetail missing =
            PropertyChatController.getPropertyDetail('No Such Project');
        PropertyChatController.PropertyDetail blank =
            PropertyChatController.getPropertyDetail('   ');
        Test.stopTest();

        Assert.areEqual('Chat Test Annexe', byName.name, 'A partial name should still resolve');
        Assert.isNull(missing, 'An unknown name returns null rather than throwing');
        Assert.isNull(blank, 'A blank key returns null rather than searching');
    }

    @isTest
    static void filtersNarrowTheResultSet() {
        makeProperties();

        Test.startTest();
        List<PropertyChatController.PropertyCard> byConfig =
            PropertyChatController.searchProperties(null, '2 BHK', null, null, null);
        List<PropertyChatController.PropertyCard> byBudget =
            PropertyChatController.searchProperties(null, null, null, 9000000, null);
        List<PropertyChatController.PropertyCard> byName =
            PropertyChatController.searchProperties(null, null, null, null, 'Tower');
        List<PropertyChatController.PropertyCard> unfiltered =
            PropertyChatController.searchProperties('All', 'Any', null, null, null);
        Test.stopTest();

        Assert.areEqual(1, byConfig.size(), 'Only the 2 BHK property matches');
        Assert.areEqual('Chat Test Annexe', byConfig[0].name);
        Assert.areEqual(1, byBudget.size(), 'Only the cheaper property fits under 90 lakh');
        Assert.areEqual(1, byName.size(), 'The name filter should isolate the Tower');
        Assert.areEqual(2, unfiltered.size(), '"All" and "Any" mean no filter at all');
    }

    @isTest
    static void soldOutPropertiesAreNeverOffered() {
        makeProperties();
        annexe.Status__c = 'Sold Out';
        update annexe;

        Test.startTest();
        List<PropertyChatController.PropertyCard> cards =
            PropertyChatController.searchProperties(null, null, null, null, null);
        Test.stopTest();

        Assert.areEqual(1, cards.size(), 'A sold out project must drop out of the collection');
        Assert.areEqual('Chat Test Tower', cards[0].name);
    }
}
