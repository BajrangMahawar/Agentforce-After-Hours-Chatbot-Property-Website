public without sharing class PropertyPortalController {
    private static final Integer MAX_RESULTS = 60;
    private static final String LOG = 'PORTAL';

    @AuraEnabled(cacheable=true)
    public static List<PropertyCard> getProperties(String city, String configuration, Decimal priceMin, Decimal priceMax) {
        AgentforceLogger.log(LOG, 'GET_PROPERTIES',
            'city=' + AgentforceLogger.show(city) +
            ' configuration=' + AgentforceLogger.show(configuration) +
            ' priceMin=' + AgentforceLogger.show(priceMin) +
            ' priceMax=' + AgentforceLogger.show(priceMax));
        List<String> filters = new List<String>{ 'Status__c != \'Sold Out\'' };
        Map<String, Object> binds = new Map<String, Object>();

        if (String.isNotBlank(city) && city != 'All') {
            binds.put('city', '%' + city.trim() + '%');
            filters.add('City__c LIKE :city');
        }
        if (String.isNotBlank(configuration) && configuration != 'All') {
            binds.put('config', configuration.trim());
            filters.add('Configurations__c INCLUDES (:config)');
        }
        if (priceMin != null && priceMin > 0) {
            binds.put('minBudget', priceMin);
            filters.add('(Price_Max__c >= :minBudget OR (Price_Max__c = NULL AND Price_Min__c >= :minBudget))');
        }
        if (priceMax != null && priceMax > 0) {
            binds.put('maxBudget', priceMax);
            filters.add('(Price_Min__c <= :maxBudget OR (Price_Min__c = NULL AND Price_Max__c <= :maxBudget))');
        }

        String soql =
            'SELECT Id, Name, City__c, Address__c, Configurations__c, Property_Type__c, Status__c, ' +
            'Price_Min__c, Price_Max__c, Price_Range__c, Possession_Date__c, RERA_Number__c, Description__c ' +
            'FROM Property__c WHERE ' + String.join(filters, ' AND ') +
            ' ORDER BY Price_Min__c DESC NULLS LAST, Name ASC LIMIT ' + MAX_RESULTS;

        AgentforceLogger.log(LOG, 'GET_PROPERTIES', 'soql=' + soql + ' binds=' + binds);

        List<PropertyCard> cards = new List<PropertyCard>();
        for (Property__c p : (List<Property__c>) Database.queryWithBinds(soql, binds, AccessLevel.SYSTEM_MODE)) {
            cards.add(new PropertyCard(p));
        }
        AgentforceLogger.log(LOG, 'GET_PROPERTIES', 'returned ' + cards.size() + ' card(s)');
        return cards;
    }

    @AuraEnabled(cacheable=true)
    public static List<String> getCities() {
        Set<String> cities = new Set<String>();
        for (AggregateResult ar : [
            SELECT City__c city FROM Property__c
            WHERE City__c != NULL AND Status__c != 'Sold Out'
            GROUP BY City__c ORDER BY City__c
        ]) {
            cities.add((String) ar.get('city'));
        }
        List<String> sorted = new List<String>(cities);
        sorted.sort();
        AgentforceLogger.log(LOG, 'GET_CITIES', 'returned ' + sorted.size() + ' city(s)');
        return sorted;
    }

    @AuraEnabled(cacheable=true)
    public static List<String> getConfigurations() {
        List<String> values = new List<String>();
        for (Schema.PicklistEntry entry : Property__c.Configurations__c.getDescribe().getPicklistValues()) {
            if (entry.isActive()) {
                values.add(entry.getValue());
            }
        }
        AgentforceLogger.log(LOG, 'GET_CONFIGURATIONS', 'returned ' + values.size() + ' active value(s)');
        return values;
    }

    public class PropertyCard {
        @AuraEnabled public String recordId;
        @AuraEnabled public String name;
        @AuraEnabled public String city;
        @AuraEnabled public String address;
        @AuraEnabled public String configurations;
        @AuraEnabled public String propertyType;
        @AuraEnabled public String status;
        @AuraEnabled public String priceRange;
        @AuraEnabled public Decimal priceMin;
        @AuraEnabled public Decimal priceMax;
        @AuraEnabled public String possession;
        @AuraEnabled public String reraNumber;
        @AuraEnabled public String description;
        @AuraEnabled public String initials;

        public PropertyCard(Property__c p) {
            this.recordId = p.Id;
            this.name = p.Name;
            this.city = p.City__c;
            this.address = p.Address__c;
            this.configurations = p.Configurations__c == null ? '' : p.Configurations__c.replace(';', ' · ');
            this.propertyType = p.Property_Type__c;
            this.status = p.Status__c;
            this.priceRange = String.isBlank(p.Price_Range__c) ? 'Price on request' : p.Price_Range__c;
            this.priceMin = p.Price_Min__c;
            this.priceMax = p.Price_Max__c;
            this.possession = p.Possession_Date__c == null
                ? 'Possession on request'
                : p.Possession_Date__c.year() <= Date.today().year()
                    ? 'Ready to move'
                    : monthName(p.Possession_Date__c.month()) + ' ' + p.Possession_Date__c.year();
            this.reraNumber = p.RERA_Number__c;
            this.description = p.Description__c;
            this.initials = initialsOf(p.Name);
        }

        private String initialsOf(String value) {
            if (String.isBlank(value)) {
                return '--';
            }
            List<String> words = value.trim().split('\\s+');
            String first = words[0].substring(0, 1);
            String second = words.size() > 1 ? words[1].substring(0, 1) : '';
            return (first + second).toUpperCase();
        }

        private String monthName(Integer month) {
            return new List<String>{
                'January', 'February', 'March', 'April', 'May', 'June',
                'July', 'August', 'September', 'October', 'November', 'December'
            }[month - 1];
        }
    }
}
