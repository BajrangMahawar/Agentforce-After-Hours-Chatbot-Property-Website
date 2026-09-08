/**
 * Sample inventory for the five business segments: Commercial Leasing, Luxury Residential,
 * Clubs, Warehousing and Senior Living - across the NCR belt plus Bhiwadi.
 *
 * Same rules as create-sample-data.apex: project names are real, everything else (pricing,
 * possession, RERA, mediator mapping) is invented. RERA numbers carry a SAMPLE- prefix and
 * descriptions are tagged [SAMPLE DATA].
 *
 * Mediators are reused from create-sample-data.apex, so run that first. Re-runnable: the
 * SAMPLE-SEG- records are wiped before they are rebuilt.
 *
 *   sf apex run --file scripts/apex/create-segment-properties.apex
 */

final String TAG = '[SAMPLE DATA] ';
final String EMAIL_DOMAIN = '@sampleprop.example.com';

// ---------------------------------------------------------------- clean previous run
List<Property__c> old = [SELECT Id FROM Property__c WHERE RERA_Number__c LIKE 'SAMPLE-SEG-%'];
if (!old.isEmpty()) { delete old; }        // specs + junction rows cascade
System.debug('Cleared ' + old.size() + ' segment properties.');

Map<String, Contact> med = new Map<String, Contact>();
for (Contact c : [SELECT Id, LastName FROM Contact WHERE Email LIKE :('%' + EMAIL_DOMAIN)]) {
    med.put(c.LastName, c);
}
if (med.isEmpty()) {
    throw new IllegalArgumentException('No mediators found - run scripts/apex/create-sample-data.apex first.');
}

Map<String, Property__c> p = new Map<String, Property__c>();

// ================================================================ COMMERCIAL LEASING
// Price fields carry the indicative MONTHLY RENT for leasing stock, not a sale price.
p.put('worldmark', new Property__c(
    Name = 'Worldmark Aerocity', City__c = 'Delhi', Address__c = 'Aerocity, NH-8, New Delhi 110037',
    Configurations__c = 'Office Space;Shop', Property_Type__c = 'Commercial Office', Status__c = 'Ready to Move',
    Price_Min__c = 250000, Price_Max__c = 1800000, Possession_Date__c = Date.newInstance(2018, 4, 30),
    RERA_Number__c = 'SAMPLE-SEG-0001', Location__Latitude__s = 28.5527, Location__Longitude__s = 77.1214,
    Description__c = TAG + 'COMMERCIAL LEASING. Grade-A office and retail blocks at Aerocity, ten minutes from T3. ' +
        'Figures shown are indicative MONTHLY RENT, not a sale price. Fitted and warm-shell options, 24x7 access, ' +
        'structured parking and a hotel cluster on the doorstep.'));

p.put('cyberpark', new Property__c(
    Name = 'DLF Cyber Park', City__c = 'Gurugram', Address__c = 'Sector 20, Old Delhi-Gurugram Road, Gurugram, Haryana 122008',
    Configurations__c = 'Office Space', Property_Type__c = 'Commercial Office', Status__c = 'Ready to Move',
    Price_Min__c = 180000, Price_Max__c = 2500000, Possession_Date__c = Date.newInstance(2020, 9, 30),
    RERA_Number__c = 'SAMPLE-SEG-0002', Location__Latitude__s = 28.4949, Location__Longitude__s = 77.0736,
    Description__c = TAG + 'COMMERCIAL LEASING. Campus-style offices with floor plates from 5,000 sq ft to a full ' +
        'tower. Indicative MONTHLY RENT. Rapid Metro connectivity, LEED Gold, and a food court across three levels.'));

// ================================================================ LUXURY RESIDENTIAL
p.put('connaughtone', new Property__c(
    Name = 'Godrej Connaught One', City__c = 'Delhi', Address__c = 'Barakhamba Road, Connaught Place, New Delhi 110001',
    Configurations__c = '2 BHK;3 BHK;4 BHK', Property_Type__c = 'Apartment', Status__c = 'Ready to Move',
    Price_Min__c = 65000000, Price_Max__c = 195000000, Possession_Date__c = Date.newInstance(2023, 12, 31),
    RERA_Number__c = 'SAMPLE-SEG-0003', Location__Latitude__s = 28.6289, Location__Longitude__s = 77.2270,
    Description__c = TAG + 'LUXURY RESIDENTIAL. The only new-build residential address inside Connaught Place, with ' +
        '2, 3 and 4 BHK homes, a rooftop lounge and concierge service. Walk to Rajiv Chowk metro.'));

p.put('trumptowers', new Property__c(
    Name = 'Trump Towers Delhi NCR', City__c = 'Gurugram', Address__c = 'Sector 65, Golf Course Extension Road, Gurugram, Haryana 122102',
    Configurations__c = '2 BHK;3 BHK;4 BHK;Penthouse', Property_Type__c = 'Apartment', Status__c = 'Ready to Move',
    Price_Min__c = 52000000, Price_Max__c = 160000000, Possession_Date__c = Date.newInstance(2024, 6, 30),
    RERA_Number__c = 'SAMPLE-SEG-0004', Location__Latitude__s = 28.3975, Location__Longitude__s = 77.0645,
    Description__c = TAG + 'LUXURY RESIDENTIAL. Branded residences on Golf Course Extension Road - 2, 3 and 4 BHK ' +
        'plus duplex penthouses, private lift lobbies, sky deck and a wellness floor.'));

// ================================================================ CLUBS
// Price fields carry the indicative MEMBERSHIP FEE.
p.put('dlfgolf', new Property__c(
    Name = 'DLF Golf & Country Club', City__c = 'Gurugram', Address__c = 'Golf Course Road, DLF Phase 5, Gurugram, Haryana 122009',
    Configurations__c = 'Club Facility', Property_Type__c = 'Club / Recreation', Status__c = 'Ready to Move',
    Price_Min__c = 4500000, Price_Max__c = 12000000, Possession_Date__c = Date.newInstance(2000, 1, 31),
    RERA_Number__c = 'SAMPLE-SEG-0005', Location__Latitude__s = 28.4595, Location__Longitude__s = 77.0980,
    Description__c = TAG + 'CLUBS. Championship 18-hole course, floodlit 9-hole, tennis, spa and fine dining. ' +
        'Figures shown are indicative MEMBERSHIP FEE, not a property price. Corporate and individual categories.'));

p.put('jaypeeclub', new Property__c(
    Name = 'Jaypee Greens Golf & Spa Club', City__c = 'Greater Noida', Address__c = 'Jaypee Greens, Surajpur, Greater Noida, Uttar Pradesh 201306',
    Configurations__c = 'Club Facility', Property_Type__c = 'Club / Recreation', Status__c = 'Ready to Move',
    Price_Min__c = 2500000, Price_Max__c = 7500000, Possession_Date__c = Date.newInstance(2005, 6, 30),
    RERA_Number__c = 'SAMPLE-SEG-0006', Location__Latitude__s = 28.4645, Location__Longitude__s = 77.5085,
    Description__c = TAG + 'CLUBS. Greg Norman signature course inside a 452-acre township, with a spa, banquet ' +
        'lawns and racquet courts. Indicative MEMBERSHIP FEE. Family and single memberships available.'));

// ================================================================ WAREHOUSING
p.put('indospace', new Property__c(
    Name = 'IndoSpace Logistics Park Farukhnagar', City__c = 'Gurugram', Address__c = 'Farukhnagar, Pataudi Road, Gurugram, Haryana 122506',
    Configurations__c = 'Warehouse Unit', Property_Type__c = 'Warehouse / Logistics', Status__c = 'Ready to Move',
    Price_Min__c = 550000, Price_Max__c = 9000000, Possession_Date__c = Date.newInstance(2021, 11, 30),
    RERA_Number__c = 'SAMPLE-SEG-0007', Location__Latitude__s = 28.4453, Location__Longitude__s = 76.8236,
    Description__c = TAG + 'WAREHOUSING. Grade-A logistics park on Pataudi Road with 12 m clear height, dock ' +
        'levellers and 40 m truck courts. Figures shown are indicative MONTHLY RENT, from a 25,000 sq ft bay ' +
        'to a 300,000 sq ft block at INR 22-30 per sq ft. Build-to-suit available.'));

p.put('welspunone', new Property__c(
    Name = 'Welspun One Logistics Park NCR', City__c = 'Ghaziabad', Address__c = 'NH-9, Dasna, Ghaziabad, Uttar Pradesh 201015',
    Configurations__c = 'Warehouse Unit', Property_Type__c = 'Warehouse / Logistics', Status__c = 'Under Construction',
    Price_Min__c = 570000, Price_Max__c = 6500000, Possession_Date__c = Date.newInstance(2027, 3, 31),
    RERA_Number__c = 'SAMPLE-SEG-0008', Location__Latitude__s = 28.6803, Location__Longitude__s = 77.5215,
    Description__c = TAG + 'WAREHOUSING. Institutional-grade park on NH-9 serving east Delhi and west UP. ' +
        'Figures shown are indicative MONTHLY RENT, from a 30,000 sq ft bay to a 250,000 sq ft block at ' +
        'INR 19-26 per sq ft. FM-2 compliant flooring, ESFR sprinklers, and 24x7 security.'));

// ================================================================ SENIOR LIVING
p.put('antara', new Property__c(
    Name = 'Antara Senior Living Noida', City__c = 'Noida', Address__c = 'Sector 150, Noida Expressway, Noida, Uttar Pradesh 201310',
    Configurations__c = 'Studio;1 BHK;2 BHK;3 BHK', Property_Type__c = 'Senior Living', Status__c = 'Under Construction',
    Price_Min__c = 12500000, Price_Max__c = 42000000, Possession_Date__c = Date.newInstance(2028, 9, 30),
    RERA_Number__c = 'SAMPLE-SEG-0009', Location__Latitude__s = 28.4265, Location__Longitude__s = 77.5015,
    Description__c = TAG + 'SENIOR LIVING. Age-friendly residences with 2 BHK and larger options, on-site clinic, ' +
        'physiotherapy, chef-run dining and 24x7 emergency response. Step-free layouts, grab rails and ' +
        'anti-skid flooring throughout.'));

p.put('ashiana', new Property__c(
    Name = 'Ashiana Nirmay', City__c = 'Bhiwadi', Address__c = 'Alwar Bypass Road, Bhiwadi, Rajasthan 301019',
    Configurations__c = '1 BHK;2 BHK;3 BHK', Property_Type__c = 'Senior Living', Status__c = 'Ready to Move',
    Price_Min__c = 4500000, Price_Max__c = 11500000, Possession_Date__c = Date.newInstance(2022, 3, 31),
    RERA_Number__c = 'SAMPLE-SEG-0010', Location__Latitude__s = 28.2103, Location__Longitude__s = 76.8606,
    Description__c = TAG + 'SENIOR LIVING. Established senior community an hour from Gurugram, with 2 BHK and 3 BHK ' +
        'homes, a daily-meals plan, nurse on call, and an activity calendar run by the resident association.'));

insert p.values();
System.debug('Inserted ' + p.size() + ' segment properties.');

// ---------------------------------------------------------------- specifications
final String OFFICE_AMEN = 'Covered Parking;Visitor Parking;Power Backup;24x7 Security;CCTV Surveillance;Elevator;Fire Safety System;Convenience Store';
final String LUX_AMEN = 'Swimming Pool;Gymnasium;Clubhouse;Landscaped Garden;Covered Parking;Power Backup;24x7 Security;CCTV Surveillance;Elevator;Fire Safety System;Yoga / Meditation Deck;Co-working Space';
final String CLUB_AMEN = 'Swimming Pool;Gymnasium;Clubhouse;Sports Court;Multipurpose Hall;Indoor Games Room;Landscaped Garden;Visitor Parking;Power Backup;24x7 Security';
final String WHSE_AMEN = 'Covered Parking;Power Backup;24x7 Security;CCTV Surveillance;Fire Safety System;Rainwater Harvesting';
final String SENIOR_AMEN = 'Clubhouse;Landscaped Garden;Jogging Track;Yoga / Meditation Deck;Senior Citizen Area;Multipurpose Hall;Power Backup;24x7 Security;Elevator;Intercom;Fire Safety System';

insert new List<Property_Specification__c>{
    // Commercial leasing
    new Property_Specification__c(Name = 'Worldmark Office Floor', Property__c = p.get('worldmark').Id, Unit_Type__c = 'Office Space', Carpet_Area__c = 4200, Built_up_Area__c = 6000, Amenities__c = OFFICE_AMEN),
    new Property_Specification__c(Name = 'Worldmark Retail Unit', Property__c = p.get('worldmark').Id, Unit_Type__c = 'Shop', Carpet_Area__c = 900, Built_up_Area__c = 1250, Amenities__c = OFFICE_AMEN),
    new Property_Specification__c(Name = 'Cyber Park Half Floor', Property__c = p.get('cyberpark').Id, Unit_Type__c = 'Office Space', Carpet_Area__c = 7500, Built_up_Area__c = 10500, Amenities__c = OFFICE_AMEN),

    // Luxury residential - 2 BHK and larger
    new Property_Specification__c(Name = 'Connaught One 2 BHK', Property__c = p.get('connaughtone').Id, Unit_Type__c = '2 BHK', Carpet_Area__c = 1420, Built_up_Area__c = 1980, Amenities__c = LUX_AMEN, Floor_Plan_URL__c = 'https://example.com/plans/connaught-2bhk.pdf'),
    new Property_Specification__c(Name = 'Connaught One 3 BHK', Property__c = p.get('connaughtone').Id, Unit_Type__c = '3 BHK', Carpet_Area__c = 2150, Built_up_Area__c = 2950, Amenities__c = LUX_AMEN, Floor_Plan_URL__c = 'https://example.com/plans/connaught-3bhk.pdf'),
    new Property_Specification__c(Name = 'Connaught One 4 BHK', Property__c = p.get('connaughtone').Id, Unit_Type__c = '4 BHK', Carpet_Area__c = 3100, Built_up_Area__c = 4250, Amenities__c = LUX_AMEN),
    new Property_Specification__c(Name = 'Trump Towers 2 BHK', Property__c = p.get('trumptowers').Id, Unit_Type__c = '2 BHK', Carpet_Area__c = 1380, Built_up_Area__c = 1900, Amenities__c = LUX_AMEN),
    new Property_Specification__c(Name = 'Trump Towers 3 BHK', Property__c = p.get('trumptowers').Id, Unit_Type__c = '3 BHK', Carpet_Area__c = 2280, Built_up_Area__c = 3150, Amenities__c = LUX_AMEN),
    new Property_Specification__c(Name = 'Trump Towers 4 BHK', Property__c = p.get('trumptowers').Id, Unit_Type__c = '4 BHK', Carpet_Area__c = 3250, Built_up_Area__c = 4400, Amenities__c = LUX_AMEN),
    new Property_Specification__c(Name = 'Trump Towers Penthouse', Property__c = p.get('trumptowers').Id, Unit_Type__c = 'Penthouse', Carpet_Area__c = 6100, Built_up_Area__c = 8200, Amenities__c = LUX_AMEN),

    // Clubs
    new Property_Specification__c(Name = 'DLF Club Individual Membership', Property__c = p.get('dlfgolf').Id, Unit_Type__c = 'Club Facility', Amenities__c = CLUB_AMEN),
    new Property_Specification__c(Name = 'Jaypee Club Family Membership', Property__c = p.get('jaypeeclub').Id, Unit_Type__c = 'Club Facility', Amenities__c = CLUB_AMEN),

    // Warehousing
    new Property_Specification__c(Name = 'IndoSpace Standard Bay', Property__c = p.get('indospace').Id, Unit_Type__c = 'Warehouse Unit', Carpet_Area__c = 50000, Built_up_Area__c = 52000, Amenities__c = WHSE_AMEN),
    new Property_Specification__c(Name = 'Welspun One Anchor Unit', Property__c = p.get('welspunone').Id, Unit_Type__c = 'Warehouse Unit', Carpet_Area__c = 120000, Built_up_Area__c = 125000, Amenities__c = WHSE_AMEN),

    // Senior living - 2 BHK and larger alongside the smaller plans
    new Property_Specification__c(Name = 'Antara Studio', Property__c = p.get('antara').Id, Unit_Type__c = 'Studio', Carpet_Area__c = 560, Built_up_Area__c = 780, Amenities__c = SENIOR_AMEN),
    new Property_Specification__c(Name = 'Antara 2 BHK', Property__c = p.get('antara').Id, Unit_Type__c = '2 BHK', Carpet_Area__c = 1180, Built_up_Area__c = 1620, Amenities__c = SENIOR_AMEN),
    new Property_Specification__c(Name = 'Antara 3 BHK', Property__c = p.get('antara').Id, Unit_Type__c = '3 BHK', Carpet_Area__c = 1720, Built_up_Area__c = 2350, Amenities__c = SENIOR_AMEN),
    new Property_Specification__c(Name = 'Ashiana Nirmay 2 BHK', Property__c = p.get('ashiana').Id, Unit_Type__c = '2 BHK', Carpet_Area__c = 1050, Built_up_Area__c = 1440, Amenities__c = SENIOR_AMEN),
    new Property_Specification__c(Name = 'Ashiana Nirmay 3 BHK', Property__c = p.get('ashiana').Id, Unit_Type__c = '3 BHK', Carpet_Area__c = 1480, Built_up_Area__c = 2020, Amenities__c = SENIOR_AMEN)
};
System.debug('Inserted specifications.');

// ---------------------------------------------------------------- mediator coverage
Map<String, List<String>> coverage = new Map<String, List<String>>{
    'worldmark'    => new List<String>{ 'Malhotra', 'Rana' },
    'cyberpark'    => new List<String>{ 'Khurana', 'Sharma', 'Qureshi' },
    'connaughtone' => new List<String>{ 'Rana', 'Qureshi', 'Malhotra' },
    'trumptowers'  => new List<String>{ 'Sharma', 'Qureshi' },
    'dlfgolf'      => new List<String>{ 'Sharma', 'Qureshi' },
    'jaypeeclub'   => new List<String>{ 'Yadav', 'Bhatia' },
    'indospace'    => new List<String>{ 'Khurana', 'Chauhan' },
    'welspunone'   => new List<String>{ 'Chauhan', 'Yadav' },
    'antara'       => new List<String>{ 'Bhatia', 'Sethi' },
    'ashiana'      => new List<String>{ 'Aggarwal', 'Chauhan' }
};
List<Mediator_Property__c> links = new List<Mediator_Property__c>();
for (String key : coverage.keySet()) {
    for (String lastName : coverage.get(key)) {
        links.add(new Mediator_Property__c(Property__c = p.get(key).Id, Mediator__c = med.get(lastName).Id));
    }
}
insert links;
System.debug('Inserted ' + links.size() + ' mediator-property links.');

System.debug('DONE. Properties=' + [SELECT COUNT() FROM Property__c] +
             ' Specs=' + [SELECT COUNT() FROM Property_Specification__c] +
             ' Links=' + [SELECT COUNT() FROM Mediator_Property__c]);
