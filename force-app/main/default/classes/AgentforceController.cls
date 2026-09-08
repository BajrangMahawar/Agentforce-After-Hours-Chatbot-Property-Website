public with sharing class AgentforceController {
    private static final Integer MAX_RESULTS = 50;
    private static final String LOG = 'GET_PROPERTIES';

    private static final String CITY = 'city';
    private static final String CONFIG = 'config';
    private static final String PRICE = 'price';
    private static final Map<String, String> FILTER_LABELS = new Map<String, String>{
        CITY => 'city',
        CONFIG => 'configuration',
        PRICE => 'budget'
    };

    private static final List<Set<String>> FILTER_ATTEMPTS = new List<Set<String>>{
        new Set<String>{ CITY, CONFIG, PRICE },
        new Set<String>{ CITY, CONFIG },
        new Set<String>{ CITY, PRICE },
        new Set<String>{ CONFIG, PRICE },
        new Set<String>{ CITY },
        new Set<String>{ CONFIG },
        new Set<String>{ PRICE }
    };


    @InvocableMethod(
    label='Get Properties'
        description='Returns available properties matching a city, a BHK configuration and a price range. Every filter is optional, and filters are relaxed automatically when the combination matches nothing.'
        category='Property'
        )
    public static List<PropertySearchResult> getProperty(List<PropertySearchRequest> requests) {
        List<PropertySearchResult> results = new List<PropertySearchResult>();

        AgentforceLogger.logContext(LOG, requests == null ? 0 : requests.size());
        if (requests == null) {
            AgentforceLogger.log(LOG, 'ENTRY', 'ABORT: the request list itself was null');
            return results;
        }

        Integer index = 0;
        for (PropertySearchRequest req : requests) {
            index++;
            PropertySearchResult res = new PropertySearchResult();
            try {
                if (req == null) {
                    AgentforceLogger.log(LOG, 'REQUEST #' + index, 'the request object was null');
                } else {
                    AgentforceLogger.log(LOG, 'REQUEST #' + index,
                        'city=' + AgentforceLogger.show(req.city) +
                        ' configuration=' + AgentforceLogger.show(req.configuration) +
                        ' priceMin=' + AgentforceLogger.show(req.priceMin) +
                        ' priceMax=' + AgentforceLogger.show(req.priceMax));
                }
                searchWithFallback(req, res);
                res.isSuccess = true;
                AgentforceLogger.log(LOG, 'RESULT #' + index,
                    'isSuccess=true recordCount=' + res.recordCount +
                    ' isExactMatch=' + res.isExactMatch +
                    ' applied=' + AgentforceLogger.show(res.appliedFilters) +
                    ' relaxed=' + AgentforceLogger.show(res.relaxedFilters));
                AgentforceLogger.log(LOG, 'RESULT #' + index, 'message=' + AgentforceLogger.show(res.message));
            } catch (Exception e) {
                res.properties = new List<PropertyInfo>();
                res.recordCount = 0;
                res.isExactMatch = false;
                res.isSuccess = false;
                res.message = 'Could not search properties: ' + e.getMessage();
                AgentforceLogger.logException(LOG, 'EXCEPTION #' + index, e);
            }
            results.add(res);
        }
        AgentforceLogger.log(LOG, 'EXIT', 'returning ' + results.size() + ' result(s)');
        return results;
    }

    private static void searchWithFallback(PropertySearchRequest req, PropertySearchResult res) {
        Set<String> supplied = suppliedFilters(req);
        AgentforceLogger.log(LOG, 'FALLBACK', 'filters supplied by the visitor: ' + supplied);

        res.properties = new List<PropertyInfo>();
        res.recordCount = 0;
        res.isExactMatch = false;
        res.appliedFilters = '';
        res.relaxedFilters = '';

        if (supplied.isEmpty()) {
            res.properties = search(req, new Set<String>());
            res.recordCount = res.properties.size();
            res.isExactMatch = true;
            AgentforceLogger.log(LOG, 'FALLBACK',
                'no filter given, unfiltered search returned ' + res.recordCount + ' row(s)');
            res.message = res.recordCount == 0
                ? 'There is no available property in the portfolio right now.'
                : 'No filter was given, so all ' + res.recordCount + ' available property(s) are listed.';
            return;
        }

        Boolean cityGiven = supplied.contains(CITY);

        for (Set<String> attempt : FILTER_ATTEMPTS) {
            if (!supplied.containsAll(attempt)) {
                continue;
            }
            if (cityGiven && !attempt.contains(CITY)) {
                continue;
            }

            List<PropertyInfo> found = search(req, attempt);
            AgentforceLogger.log(LOG, 'FALLBACK',
                'attempt ' + attempt + ' returned ' + found.size() + ' row(s)');
            if (found.isEmpty()) {
                continue;
            }

            Set<String> dropped = new Set<String>(supplied);
            dropped.removeAll(attempt);

            res.properties = found;
            res.recordCount = found.size();
            res.isExactMatch = dropped.isEmpty();
            res.appliedFilters = describe(attempt);
            res.relaxedFilters = dropped.isEmpty() ? '' : describe(dropped);
            AgentforceLogger.log(LOG, 'FALLBACK', 'accepted attempt ' + attempt +
                (dropped.isEmpty() ? ' as an exact match' : ', relaxed ' + dropped));
            res.message = dropped.isEmpty()
                ? found.size() + ' matching property(s) found.'
                : 'No property matched ' + describe(supplied) + ' together. Showing ' + found.size() +
                ' property(s) matched on ' + res.appliedFilters + ' - ' + res.relaxedFilters + ' relaxed.';
            return;
        }

        AgentforceLogger.log(LOG, 'FALLBACK',
            'STOP: every filter combination returned nothing for ' + supplied);
        res.message = cityGiven
            ? 'There is no available property in ' + blankToNull(req.city) + '.'
            : 'No property found for the given ' + describe(supplied) + '.';
    }

    private static Set<String> suppliedFilters(PropertySearchRequest req) {
        Set<String> supplied = new Set<String>();
        if (blankToNull(req.city) != null) {
            supplied.add(CITY);
        }
        if (blankToNull(req.configuration) != null) {
            supplied.add(CONFIG);
        }
        if ((req.priceMin != null && req.priceMin > 0) || req.priceMax != null) {
            supplied.add(PRICE);
        }
        return supplied;
    }

    private static String describe(Set<String> filters) {
        List<String> labels = new List<String>();
        for (String key : new List<String>{ CITY, CONFIG, PRICE }) {
            if (filters.contains(key)) {
                labels.add(FILTER_LABELS.get(key));
            }
        }
        if (labels.isEmpty()) {
            return 'nothing';
        }
        if (labels.size() == 1) {
            return labels[0];
        }
        String last = labels.remove(labels.size() - 1);
        return String.join(labels, ', ') + ' and ' + last;
    }

    private static List<PropertyInfo> search(PropertySearchRequest req, Set<String> active) {
        Decimal minBudget = (req.priceMin == null || req.priceMin < 0) ? 0 : req.priceMin;
        Decimal maxBudget = req.priceMax;                   // null == no upper limit
        if (maxBudget != null && maxBudget < minBudget) {    // visitor swapped the two
            Decimal swap = minBudget;
            minBudget = maxBudget;
            maxBudget = swap;
        }

        List<String> filters = new List<String>();
        Map<String, Object> binds = new Map<String, Object>();

        if (active.contains(CITY)) {
            binds.put('city', '%' + escapeLike(blankToNull(req.city)) + '%');
            filters.add('City__c LIKE :city');
        }

        if (active.contains(CONFIG)) {
            binds.put('config', blankToNull(req.configuration));
            filters.add('Configurations__c INCLUDES (:config)');
        }

        if (active.contains(PRICE)) {
            binds.put('minBudget', minBudget);
            filters.add('(Price_Max__c >= :minBudget OR (Price_Max__c = NULL AND Price_Min__c >= :minBudget))');

            if (maxBudget != null) {
                binds.put('maxBudget', maxBudget);
                filters.add('(Price_Min__c <= :maxBudget OR (Price_Min__c = NULL AND Price_Max__c <= :maxBudget))');
            }
        }

        filters.add('Status__c != \'Sold Out\'');

        String soql =
            'SELECT Id, Name, City__c, Address__c, Configurations__c, Property_Type__c, Status__c, ' +
            'Price_Min__c, Price_Max__c, Price_Range__c, Possession_Date__c, RERA_Number__c, Description__c ' +
            'FROM Property__c WHERE ' + String.join(filters, ' AND ') +
            ' ORDER BY Price_Min__c NULLS LAST, Name ASC LIMIT ' + MAX_RESULTS;

        AgentforceLogger.log(LOG, 'QUERY', 'active=' + active + ' soql=' + soql);
        AgentforceLogger.log(LOG, 'QUERY', 'binds=' + binds +
            ' propertyAccessible=' + Schema.SObjectType.Property__c.isAccessible());

        List<PropertyInfo> infos = new List<PropertyInfo>();
        for (Property__c p : (List<Property__c>) Database.queryWithBinds(soql, binds, AccessLevel.USER_MODE)) {
            infos.add(new PropertyInfo(p));
        }
        AgentforceLogger.log(LOG, 'QUERY', 'returned ' + infos.size() + ' row(s)');
        return infos;
    }

    public static String blankToNull(String value) {
        return String.isBlank(value) ? null : value.trim();
    }

    public static String escapeLike(String value) {
        return String.escapeSingleQuotes(value).replace('%', '\\%').replace('_', '\\_');
    }

    public class PropertySearchRequest {
        @InvocableVariable(label='City' description='City the visitor is looking in, e.g. Gurugram. Optional; partial names are matched.')
        public String city;

        @InvocableVariable(label='Configuration (BHK)' description='One BHK configuration as stored on the property, e.g. 2 BHK, 3 BHK, Penthouse. Optional.')
        public String configuration;

        @InvocableVariable(label='Price (Min)' description='Lower end of the budget in INR. Optional; blank starts from 0.')
        public Decimal priceMin;

        @InvocableVariable(label='Price (Max)' description='Upper end of the budget in INR. Optional; blank means no upper limit.')
        public Decimal priceMax;
    }

    public class PropertySearchResult {
        @InvocableVariable(label='Success')
        public Boolean isSuccess;

        @InvocableVariable(label='Message' description='Human readable outcome the agent can say out loud.')
        public String message;

        @InvocableVariable(label='Record Count')
        public Integer recordCount;

        @InvocableVariable(label='Exact Match' description='False when filters had to be relaxed to find anything.')
        public Boolean isExactMatch;

        @InvocableVariable(label='Applied Filters' description='The filters the returned list actually satisfies.')
        public String appliedFilters;

        @InvocableVariable(label='Relaxed Filters' description='Filters the visitor gave that had to be dropped. Blank on an exact match.')
        public String relaxedFilters;

        @InvocableVariable(label='Properties')
        public List<PropertyInfo> properties;
    }

    public class PropertyInfo {
        @InvocableVariable(label='Property Id')
        public String propertyId;

        @InvocableVariable(label='Property Name')
        public String name;

        @InvocableVariable(label='City')
        public String city;

        @InvocableVariable(label='Address')
        public String address;

        @InvocableVariable(label='Configurations (BHK)')
        public String configurations;

        @InvocableVariable(label='Property Type')
        public String propertyType;

        @InvocableVariable(label='Status')
        public String status;

        @InvocableVariable(label='Price (Min)')
        public Decimal priceMin;

        @InvocableVariable(label='Price (Max)')
        public Decimal priceMax;

        @InvocableVariable(label='Price Range' description='Formatted range the chatbot should quote, e.g. INR 1.2 Cr - 1.8 Cr.')
        public String priceRange;

        @InvocableVariable(label='Possession Date')
        public Date possessionDate;

        @InvocableVariable(label='RERA Number')
        public String reraNumber;

        @InvocableVariable(label='Description')
        public String description;

        public PropertyInfo() {
        }

        public PropertyInfo(Property__c p) {
            this.propertyId = p.Id;
            this.name = p.Name;
            this.city = p.City__c;
            this.address = p.Address__c;
            this.configurations = p.Configurations__c;
            this.propertyType = p.Property_Type__c;
            this.status = p.Status__c;
            this.priceMin = p.Price_Min__c;
            this.priceMax = p.Price_Max__c;
            this.priceRange = p.Price_Range__c;
            this.possessionDate = p.Possession_Date__c;
            this.reraNumber = p.RERA_Number__c;
            this.description = p.Description__c;
        }
    }
}