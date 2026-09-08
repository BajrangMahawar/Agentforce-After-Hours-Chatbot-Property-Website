/**
 * Sample NCR portfolio for the after-hours chatbot: Delhi, Gurugram, Faridabad and Noida.
 *
 * Project names are real, everything else (pricing, possession, RERA, mediators, contact
 * details) is invented for demo purposes - RERA numbers carry a SAMPLE- prefix and every
 * description is tagged [SAMPLE DATA] so nobody mistakes this for the live portfolio.
 *
 * Re-runnable: it wipes the previous sample set first, matched on those markers.
 *
 *   sf apex run --file scripts/apex/create-sample-data.apex
 */

final String EMAIL_DOMAIN = '@sampleprop.example.com';
final String TAG = '[SAMPLE DATA] ';

// ---------------------------------------------------------------- clean previous run
List<Property__c> oldProperties = [SELECT Id FROM Property__c WHERE RERA_Number__c LIKE 'SAMPLE-%'];
List<Contact> oldMediators = [SELECT Id FROM Contact WHERE Email LIKE :('%' + EMAIL_DOMAIN)];
List<Lead> oldLeads = [SELECT Id FROM Lead WHERE Email LIKE :('%' + EMAIL_DOMAIN)];
List<ServiceAppointment> oldVisits = [SELECT Id FROM ServiceAppointment WHERE Subject LIKE 'Site visit - %'];
if (!oldVisits.isEmpty()) { delete oldVisits; }
if (!oldLeads.isEmpty()) { delete oldLeads; }
if (!oldProperties.isEmpty()) { delete oldProperties; }   // junction + specs cascade
if (!oldMediators.isEmpty()) { delete oldMediators; }
List<Account> oldFirms = [SELECT Id FROM Account WHERE Name = 'NCR Mediator Network'];
if (!oldFirms.isEmpty()) { delete oldFirms; }
System.debug('Cleared: ' + oldProperties.size() + ' properties, ' + oldMediators.size() + ' mediators.');

// ---------------------------------------------------------------- properties
Map<String, Property__c> props = new Map<String, Property__c>();

// ---- Gurugram
props.put('camellias', new Property__c(
    Name = 'DLF The Camellias', City__c = 'Gurugram', Address__c = 'Golf Course Road, Sector 42, Gurugram, Haryana 122002',
    Configurations__c = '4 BHK;4+ BHK;Penthouse', Property_Type__c = 'Apartment', Status__c = 'Ready to Move',
    Price_Min__c = 550000000, Price_Max__c = 1100000000, Possession_Date__c = Date.newInstance(2019, 12, 31),
    RERA_Number__c = 'SAMPLE-GGM-0001', Location__Latitude__s = 28.4419, Location__Longitude__s = 77.0980,
    Description__c = TAG + 'Ultra-luxury residences on Golf Course Road with a private clubhouse, spa and 10-acre landscaped deck. Low-density towers, four apartments per floor and a dedicated concierge team. Indicative pricing only.'));

props.put('m3mgolf', new Property__c(
    Name = 'M3M Golf Estate', City__c = 'Gurugram', Address__c = 'Sector 65, Golf Course Extension Road, Gurugram, Haryana 122102',
    Configurations__c = '3 BHK;4 BHK;Penthouse', Property_Type__c = 'Apartment', Status__c = 'Ready to Move',
    Price_Min__c = 45000000, Price_Max__c = 95000000, Possession_Date__c = Date.newInstance(2021, 6, 30),
    RERA_Number__c = 'SAMPLE-GGM-0002', Location__Latitude__s = 28.3985, Location__Longitude__s = 77.0620,
    Description__c = TAG + 'Golf-themed township on Golf Course Extension Road with a nine-hole course, sky clubhouse and resort-style pool deck. Well connected to Sohna Road and NH-48.'));

props.put('aristocrat', new Property__c(
    Name = 'Godrej Aristocrat', City__c = 'Gurugram', Address__c = 'Sector 49, Sohna Road, Gurugram, Haryana 122018',
    Configurations__c = '3 BHK;4 BHK', Property_Type__c = 'Apartment', Status__c = 'Under Construction',
    Price_Min__c = 42000000, Price_Max__c = 68000000, Possession_Date__c = Date.newInstance(2029, 3, 31),
    RERA_Number__c = 'SAMPLE-GGM-0003', Location__Latitude__s = 28.4211, Location__Longitude__s = 77.0450,
    Description__c = TAG + 'New-launch high rise off Sohna Road with 75 per cent open space, a 40,000 sq ft clubhouse and easy access to Golf Course Extension Road.'));

props.put('sobhacity', new Property__c(
    Name = 'Sobha City Gurgaon', City__c = 'Gurugram', Address__c = 'Sector 108, Dwarka Expressway, Gurugram, Haryana 122006',
    Configurations__c = '2 BHK;3 BHK;4 BHK', Property_Type__c = 'Apartment', Status__c = 'Ready to Move',
    Price_Min__c = 23000000, Price_Max__c = 52000000, Possession_Date__c = Date.newInstance(2023, 9, 30),
    RERA_Number__c = 'SAMPLE-GGM-0004', Location__Latitude__s = 28.5175, Location__Longitude__s = 77.0345,
    Description__c = TAG + 'Gated community on the Dwarka Expressway with a 1.5-acre central green, three clubhouses and 20 minutes to IGI Airport.'));

props.put('sigcity93', new Property__c(
    Name = 'Signature Global City 93', City__c = 'Gurugram', Address__c = 'Sector 93, New Gurugram, Haryana 122505',
    Configurations__c = '2 BHK;3 BHK', Property_Type__c = 'Apartment', Status__c = 'Under Construction',
    Price_Min__c = 16000000, Price_Max__c = 24500000, Possession_Date__c = Date.newInstance(2027, 12, 31),
    RERA_Number__c = 'SAMPLE-GGM-0005', Location__Latitude__s = 28.4102, Location__Longitude__s = 76.9345,
    Description__c = TAG + 'Independent low-rise floors in New Gurugram with stilt parking, a central park and quick access to NH-48 and the upcoming metro corridor.'));

// ---- Delhi
props.put('capgreens', new Property__c(
    Name = 'DLF Capital Greens', City__c = 'Delhi', Address__c = 'Shivaji Marg, Moti Nagar, New Delhi 110015',
    Configurations__c = '2 BHK;3 BHK;4 BHK', Property_Type__c = 'Apartment', Status__c = 'Ready to Move',
    Price_Min__c = 24000000, Price_Max__c = 46000000, Possession_Date__c = Date.newInstance(2016, 3, 31),
    RERA_Number__c = 'SAMPLE-DEL-0001', Location__Latitude__s = 28.6580, Location__Longitude__s = 77.1425,
    Description__c = TAG + 'Established gated community in West Delhi with a 5-acre central park, clubhouse and Moti Nagar metro within walking distance.'));

props.put('southestate', new Property__c(
    Name = 'Godrej South Estate', City__c = 'Delhi', Address__c = 'Okhla Phase 1, New Delhi 110020',
    Configurations__c = '3 BHK;4 BHK', Property_Type__c = 'Apartment', Status__c = 'Ready to Move',
    Price_Min__c = 45000000, Price_Max__c = 82000000, Possession_Date__c = Date.newInstance(2023, 3, 31),
    RERA_Number__c = 'SAMPLE-DEL-0002', Location__Latitude__s = 28.5355, Location__Longitude__s = 77.2730,
    Description__c = TAG + 'Boutique South Delhi address next to Okhla Bird Sanctuary metro, with a rooftop infinity pool and views of the Kalindi Kunj green belt.'));

props.put('tripundra', new Property__c(
    Name = 'TARC Tripundra', City__c = 'Delhi', Address__c = 'Bijwasan, Kapashera, New Delhi 110061',
    Configurations__c = '3 BHK;4 BHK', Property_Type__c = 'Apartment', Status__c = 'Under Construction',
    Price_Min__c = 50000000, Price_Max__c = 78000000, Possession_Date__c = Date.newInstance(2028, 6, 30),
    RERA_Number__c = 'SAMPLE-DEL-0003', Location__Latitude__s = 28.5388, Location__Longitude__s = 77.0685,
    Description__c = TAG + 'Low-density towers near the Delhi-Gurugram border, 15 minutes from IGI Airport, with a 20,000 sq ft clubhouse and temperature-controlled pool.'));

props.put('amaryllis', new Property__c(
    Name = 'The Amaryllis', City__c = 'Delhi', Address__c = 'Karol Bagh, Central Delhi, New Delhi 110005',
    Configurations__c = '3 BHK;4 BHK;Penthouse', Property_Type__c = 'Apartment', Status__c = 'Under Construction',
    Price_Min__c = 35000000, Price_Max__c = 130000000, Possession_Date__c = Date.newInstance(2027, 9, 30),
    RERA_Number__c = 'SAMPLE-DEL-0004', Location__Latitude__s = 28.6520, Location__Longitude__s = 77.1875,
    Description__c = TAG + 'Central Delhi high rise off Panchkuian Road with landscaped podiums, a sports arena and Karol Bagh metro nearby.'));

// ---- Noida
props.put('knightsbridge', new Property__c(
    Name = 'ATS Knightsbridge', City__c = 'Noida', Address__c = 'Sector 124, Noida Expressway, Noida, Uttar Pradesh 201301',
    Configurations__c = '4 BHK;Penthouse', Property_Type__c = 'Apartment', Status__c = 'Ready to Move',
    Price_Min__c = 120000000, Price_Max__c = 240000000, Possession_Date__c = Date.newInstance(2022, 12, 31),
    RERA_Number__c = 'SAMPLE-NOI-0001', Location__Latitude__s = 28.5405, Location__Longitude__s = 77.3355,
    Description__c = TAG + 'Only 80 apartments across the project, each a full floor, overlooking the Noida golf course. Private lift lobbies and a 45,000 sq ft clubhouse.'));

props.put('godrejwoods', new Property__c(
    Name = 'Godrej Woods', City__c = 'Noida', Address__c = 'Sector 43, Noida, Uttar Pradesh 201301',
    Configurations__c = '2 BHK;3 BHK;4 BHK', Property_Type__c = 'Apartment', Status__c = 'Under Construction',
    Price_Min__c = 27000000, Price_Max__c = 58000000, Possession_Date__c = Date.newInstance(2027, 6, 30),
    RERA_Number__c = 'SAMPLE-NOI-0002', Location__Latitude__s = 28.5665, Location__Longitude__s = 77.3565,
    Description__c = TAG + 'Forest-themed towers in Sector 43 with 2,000 trees on site, a 3-acre central green and Noida Golf Course five minutes away.'));

props.put('maxestates128', new Property__c(
    Name = 'Max Estates 128', City__c = 'Noida', Address__c = 'Sector 128, Noida Expressway, Noida, Uttar Pradesh 201304',
    Configurations__c = '3 BHK;4 BHK', Property_Type__c = 'Apartment', Status__c = 'Under Construction',
    Price_Min__c = 40000000, Price_Max__c = 72000000, Possession_Date__c = Date.newInstance(2028, 12, 31),
    RERA_Number__c = 'SAMPLE-NOI-0003', Location__Latitude__s = 28.5040, Location__Longitude__s = 77.3760,
    Description__c = TAG + 'Wellness-led residences on the Noida Expressway backing on to the Jaypee Greens golf course, with biophilic design and a 60,000 sq ft club.'));

props.put('county107', new Property__c(
    Name = 'County 107', City__c = 'Noida', Address__c = 'Sector 107, Noida, Uttar Pradesh 201301',
    Configurations__c = '3 BHK;4 BHK', Property_Type__c = 'Apartment', Status__c = 'Ready to Move',
    Price_Min__c = 22000000, Price_Max__c = 38000000, Possession_Date__c = Date.newInstance(2021, 3, 31),
    RERA_Number__c = 'SAMPLE-NOI-0004', Location__Latitude__s = 28.5335, Location__Longitude__s = 77.3405,
    Description__c = TAG + 'Ready-to-move towers in Sector 107 with large balconies, a cricket practice pitch and direct Expressway access.'));

props.put('acedivino', new Property__c(
    Name = 'Ace Divino', City__c = 'Noida', Address__c = 'Sector 1, Greater Noida West, Uttar Pradesh 201306',
    Configurations__c = '2 BHK;3 BHK', Property_Type__c = 'Apartment', Status__c = 'Under Construction',
    Price_Min__c = 9500000, Price_Max__c = 18500000, Possession_Date__c = Date.newInstance(2027, 3, 31),
    RERA_Number__c = 'SAMPLE-NOI-0005', Location__Latitude__s = 28.6085, Location__Longitude__s = 77.4340,
    Description__c = TAG + 'Value-led towers in Greater Noida West with a 12,000 sq ft clubhouse, rooftop cafe and schools within the sector.'));

// ---- Faridabad
props.put('amstoria', new Property__c(
    Name = 'BPTP Amstoria Verti-Greens', City__c = 'Faridabad', Address__c = 'Sector 102, Neharpar, Faridabad, Haryana 121101',
    Configurations__c = '3 BHK;4 BHK', Property_Type__c = 'Apartment', Status__c = 'Under Construction',
    Price_Min__c = 13500000, Price_Max__c = 22000000, Possession_Date__c = Date.newInstance(2028, 3, 31),
    RERA_Number__c = 'SAMPLE-FBD-0001', Location__Latitude__s = 28.3860, Location__Longitude__s = 77.3480,
    Description__c = TAG + 'Vertical-garden towers in Greater Faridabad with a landscaped podium, banquet lawn and quick access to the Faridabad-Noida-Ghaziabad Expressway.'));

props.put('omaxeheights', new Property__c(
    Name = 'Omaxe Heights Faridabad', City__c = 'Faridabad', Address__c = 'Sector 86, Greater Faridabad, Haryana 121002',
    Configurations__c = '2 BHK;3 BHK', Property_Type__c = 'Apartment', Status__c = 'Ready to Move',
    Price_Min__c = 6000000, Price_Max__c = 11000000, Possession_Date__c = Date.newInstance(2018, 6, 30),
    RERA_Number__c = 'SAMPLE-FBD-0002', Location__Latitude__s = 28.3705, Location__Longitude__s = 77.3245,
    Description__c = TAG + 'Ready-to-move mid-rise community in Sector 86 with power backup, a swimming pool and a school inside the campus.'));

props.put('rpssavana', new Property__c(
    Name = 'RPS Savana', City__c = 'Faridabad', Address__c = 'Sector 88, Greater Faridabad, Haryana 121002',
    Configurations__c = '2 BHK;3 BHK;4 BHK', Property_Type__c = 'Apartment', Status__c = 'Ready to Move',
    Price_Min__c = 8500000, Price_Max__c = 16000000, Possession_Date__c = Date.newInstance(2019, 12, 31),
    RERA_Number__c = 'SAMPLE-FBD-0003', Location__Latitude__s = 28.3620, Location__Longitude__s = 77.3320,
    Description__c = TAG + 'Township in Sector 88 with a clubhouse, jogging track and a commercial high street inside the gate.'));

props.put('puriaravalis', new Property__c(
    Name = 'Puri Aravallis Faridabad', City__c = 'Faridabad', Address__c = 'Sector 14, Faridabad, Haryana 121007',
    Configurations__c = '3 BHK;4 BHK;Penthouse', Property_Type__c = 'Apartment', Status__c = 'Pre-Launch',
    Price_Min__c = 21000000, Price_Max__c = 42000000, Possession_Date__c = Date.newInstance(2030, 6, 30),
    RERA_Number__c = 'SAMPLE-FBD-0004', Location__Latitude__s = 28.4025, Location__Longitude__s = 77.3110,
    Description__c = TAG + 'Pre-launch luxury towers in old Faridabad facing the Aravalli ridge, with a wellness club and terrace gardens. Pricing indicative.'));

insert props.values();
System.debug('Inserted ' + props.size() + ' properties.');

// ---------------------------------------------------------------- specifications
List<Property_Specification__c> specs = new List<Property_Specification__c>();
final String LUX_AMENITIES = 'Swimming Pool;Gymnasium;Clubhouse;Landscaped Garden;Covered Parking;Power Backup;24x7 Security;CCTV Surveillance;Elevator;Fire Safety System;Yoga / Meditation Deck;Sports Court';
final String MID_AMENITIES = 'Swimming Pool;Gymnasium;Clubhouse;Kids Play Area;Jogging Track;Covered Parking;Power Backup;24x7 Security;Elevator;Rainwater Harvesting';
final String VALUE_AMENITIES = 'Gymnasium;Kids Play Area;Landscaped Garden;Visitor Parking;Power Backup;24x7 Security;Elevator;Intercom';

specs.add(new Property_Specification__c(Name = 'Camellias 4 BHK', Property__c = props.get('camellias').Id, Unit_Type__c = '4 BHK', Carpet_Area__c = 5200, Built_up_Area__c = 7350, Amenities__c = LUX_AMENITIES, Floor_Plan_URL__c = 'https://example.com/plans/camellias-4bhk.pdf'));
specs.add(new Property_Specification__c(Name = 'Camellias Penthouse', Property__c = props.get('camellias').Id, Unit_Type__c = 'Penthouse', Carpet_Area__c = 11500, Built_up_Area__c = 16000, Amenities__c = LUX_AMENITIES, Floor_Plan_URL__c = 'https://example.com/plans/camellias-penthouse.pdf'));
specs.add(new Property_Specification__c(Name = 'M3M Golf Estate 3 BHK', Property__c = props.get('m3mgolf').Id, Unit_Type__c = '3 BHK', Carpet_Area__c = 1850, Built_up_Area__c = 2650, Amenities__c = LUX_AMENITIES));
specs.add(new Property_Specification__c(Name = 'M3M Golf Estate 4 BHK', Property__c = props.get('m3mgolf').Id, Unit_Type__c = '4 BHK', Carpet_Area__c = 2600, Built_up_Area__c = 3600, Amenities__c = LUX_AMENITIES));
specs.add(new Property_Specification__c(Name = 'Aristocrat 3 BHK', Property__c = props.get('aristocrat').Id, Unit_Type__c = '3 BHK', Carpet_Area__c = 1780, Built_up_Area__c = 2450, Amenities__c = LUX_AMENITIES));
specs.add(new Property_Specification__c(Name = 'Aristocrat 4 BHK', Property__c = props.get('aristocrat').Id, Unit_Type__c = '4 BHK', Carpet_Area__c = 2450, Built_up_Area__c = 3300, Amenities__c = LUX_AMENITIES));
specs.add(new Property_Specification__c(Name = 'Sobha City 2 BHK', Property__c = props.get('sobhacity').Id, Unit_Type__c = '2 BHK', Carpet_Area__c = 1050, Built_up_Area__c = 1450, Amenities__c = MID_AMENITIES));
specs.add(new Property_Specification__c(Name = 'Sobha City 3 BHK', Property__c = props.get('sobhacity').Id, Unit_Type__c = '3 BHK', Carpet_Area__c = 1520, Built_up_Area__c = 2100, Amenities__c = MID_AMENITIES));
specs.add(new Property_Specification__c(Name = 'City 93 2 BHK', Property__c = props.get('sigcity93').Id, Unit_Type__c = '2 BHK', Carpet_Area__c = 890, Built_up_Area__c = 1250, Amenities__c = VALUE_AMENITIES));
specs.add(new Property_Specification__c(Name = 'City 93 3 BHK', Property__c = props.get('sigcity93').Id, Unit_Type__c = '3 BHK', Carpet_Area__c = 1260, Built_up_Area__c = 1720, Amenities__c = VALUE_AMENITIES));
specs.add(new Property_Specification__c(Name = 'Capital Greens 2 BHK', Property__c = props.get('capgreens').Id, Unit_Type__c = '2 BHK', Carpet_Area__c = 1080, Built_up_Area__c = 1480, Amenities__c = MID_AMENITIES));
specs.add(new Property_Specification__c(Name = 'Capital Greens 3 BHK', Property__c = props.get('capgreens').Id, Unit_Type__c = '3 BHK', Carpet_Area__c = 1560, Built_up_Area__c = 2150, Amenities__c = MID_AMENITIES));
specs.add(new Property_Specification__c(Name = 'South Estate 3 BHK', Property__c = props.get('southestate').Id, Unit_Type__c = '3 BHK', Carpet_Area__c = 1700, Built_up_Area__c = 2400, Amenities__c = LUX_AMENITIES));
specs.add(new Property_Specification__c(Name = 'South Estate 4 BHK', Property__c = props.get('southestate').Id, Unit_Type__c = '4 BHK', Carpet_Area__c = 2350, Built_up_Area__c = 3200, Amenities__c = LUX_AMENITIES));
specs.add(new Property_Specification__c(Name = 'Tripundra 3 BHK', Property__c = props.get('tripundra').Id, Unit_Type__c = '3 BHK', Carpet_Area__c = 1950, Built_up_Area__c = 2700, Amenities__c = LUX_AMENITIES));
specs.add(new Property_Specification__c(Name = 'Amaryllis 3 BHK', Property__c = props.get('amaryllis').Id, Unit_Type__c = '3 BHK', Carpet_Area__c = 1450, Built_up_Area__c = 2050, Amenities__c = LUX_AMENITIES));
specs.add(new Property_Specification__c(Name = 'Amaryllis Penthouse', Property__c = props.get('amaryllis').Id, Unit_Type__c = 'Penthouse', Carpet_Area__c = 4200, Built_up_Area__c = 5800, Amenities__c = LUX_AMENITIES));
specs.add(new Property_Specification__c(Name = 'Knightsbridge 4 BHK', Property__c = props.get('knightsbridge').Id, Unit_Type__c = '4 BHK', Carpet_Area__c = 5800, Built_up_Area__c = 8100, Amenities__c = LUX_AMENITIES));
specs.add(new Property_Specification__c(Name = 'Godrej Woods 2 BHK', Property__c = props.get('godrejwoods').Id, Unit_Type__c = '2 BHK', Carpet_Area__c = 1020, Built_up_Area__c = 1420, Amenities__c = MID_AMENITIES));
specs.add(new Property_Specification__c(Name = 'Godrej Woods 3 BHK', Property__c = props.get('godrejwoods').Id, Unit_Type__c = '3 BHK', Carpet_Area__c = 1480, Built_up_Area__c = 2050, Amenities__c = MID_AMENITIES));
specs.add(new Property_Specification__c(Name = 'Max 128 3 BHK', Property__c = props.get('maxestates128').Id, Unit_Type__c = '3 BHK', Carpet_Area__c = 1820, Built_up_Area__c = 2500, Amenities__c = LUX_AMENITIES));
specs.add(new Property_Specification__c(Name = 'Max 128 4 BHK', Property__c = props.get('maxestates128').Id, Unit_Type__c = '4 BHK', Carpet_Area__c = 2400, Built_up_Area__c = 3250, Amenities__c = LUX_AMENITIES));
specs.add(new Property_Specification__c(Name = 'County 107 3 BHK', Property__c = props.get('county107').Id, Unit_Type__c = '3 BHK', Carpet_Area__c = 1400, Built_up_Area__c = 1950, Amenities__c = MID_AMENITIES));
specs.add(new Property_Specification__c(Name = 'Ace Divino 2 BHK', Property__c = props.get('acedivino').Id, Unit_Type__c = '2 BHK', Carpet_Area__c = 820, Built_up_Area__c = 1150, Amenities__c = VALUE_AMENITIES));
specs.add(new Property_Specification__c(Name = 'Ace Divino 3 BHK', Property__c = props.get('acedivino').Id, Unit_Type__c = '3 BHK', Carpet_Area__c = 1180, Built_up_Area__c = 1625, Amenities__c = VALUE_AMENITIES));
specs.add(new Property_Specification__c(Name = 'Amstoria 3 BHK', Property__c = props.get('amstoria').Id, Unit_Type__c = '3 BHK', Carpet_Area__c = 1350, Built_up_Area__c = 1875, Amenities__c = MID_AMENITIES));
specs.add(new Property_Specification__c(Name = 'Amstoria 4 BHK', Property__c = props.get('amstoria').Id, Unit_Type__c = '4 BHK', Carpet_Area__c = 1780, Built_up_Area__c = 2450, Amenities__c = MID_AMENITIES));
specs.add(new Property_Specification__c(Name = 'Omaxe Heights 2 BHK', Property__c = props.get('omaxeheights').Id, Unit_Type__c = '2 BHK', Carpet_Area__c = 780, Built_up_Area__c = 1075, Amenities__c = VALUE_AMENITIES));
specs.add(new Property_Specification__c(Name = 'Omaxe Heights 3 BHK', Property__c = props.get('omaxeheights').Id, Unit_Type__c = '3 BHK', Carpet_Area__c = 1120, Built_up_Area__c = 1550, Amenities__c = VALUE_AMENITIES));
specs.add(new Property_Specification__c(Name = 'RPS Savana 2 BHK', Property__c = props.get('rpssavana').Id, Unit_Type__c = '2 BHK', Carpet_Area__c = 950, Built_up_Area__c = 1310, Amenities__c = VALUE_AMENITIES));
specs.add(new Property_Specification__c(Name = 'RPS Savana 3 BHK', Property__c = props.get('rpssavana').Id, Unit_Type__c = '3 BHK', Carpet_Area__c = 1310, Built_up_Area__c = 1800, Amenities__c = VALUE_AMENITIES));
specs.add(new Property_Specification__c(Name = 'Puri Aravallis 3 BHK', Property__c = props.get('puriaravalis').Id, Unit_Type__c = '3 BHK', Carpet_Area__c = 1650, Built_up_Area__c = 2280, Amenities__c = LUX_AMENITIES));
specs.add(new Property_Specification__c(Name = 'Puri Aravallis 4 BHK', Property__c = props.get('puriaravalis').Id, Unit_Type__c = '4 BHK', Carpet_Area__c = 2200, Built_up_Area__c = 3000, Amenities__c = LUX_AMENITIES));
insert specs;
System.debug('Inserted ' + specs.size() + ' specifications.');

// ---------------------------------------------------------------- mediators (Contacts)
// Contacts MUST hang off an Account. Contact sharing here is Controlled by Parent, so a
// Contact with no Account is a private record only its owner can read - which makes the
// Mediator-Property junction (ControlledByParent on Contact) invisible to the Agentforce
// agent user, and every availability check answers "no mediator is mapped".
Account firm = new Account(Name = 'NCR Mediator Network',
    Description = TAG + 'Holding account for the mediator network. Keeps mediator Contacts readable by the agent user.');
insert firm;

Map<String, Contact> med = new Map<String, Contact>();
med.put('rohit',   new Contact(AccountId = firm.Id, FirstName = 'Rohit',   LastName = 'Malhotra',  Title = 'Senior Property Advisor', Phone = '011-4155-2201', MobilePhone = '+91-98110-45201', Email = 'rohit.malhotra' + EMAIL_DOMAIN, Description = TAG + 'Covers Central and West Delhi.'));
med.put('priya',   new Contact(AccountId = firm.Id, FirstName = 'Priya',   LastName = 'Sharma',    Title = 'Luxury Homes Specialist', Phone = '0124-425-3310', MobilePhone = '+91-98180-45202', Email = 'priya.sharma' + EMAIL_DOMAIN, Description = TAG + 'Golf Course Road and Golf Course Extension.'));
med.put('aman',    new Contact(AccountId = firm.Id, FirstName = 'Aman',    LastName = 'Khurana',   Title = 'Property Advisor',        Phone = '0124-425-3311', MobilePhone = '+91-98717-45203', Email = 'aman.khurana' + EMAIL_DOMAIN, Description = TAG + 'New Gurugram and Dwarka Expressway.'));
med.put('neha',    new Contact(AccountId = firm.Id, FirstName = 'Neha',    LastName = 'Bhatia',    Title = 'Senior Property Advisor', Phone = '0120-457-8820', MobilePhone = '+91-99100-45204', Email = 'neha.bhatia' + EMAIL_DOMAIN, Description = TAG + 'Noida Expressway corridor.'));
med.put('vikram',  new Contact(AccountId = firm.Id, FirstName = 'Vikram',  LastName = 'Sethi',     Title = 'Luxury Homes Specialist', Phone = '0120-457-8821', MobilePhone = '+91-99711-45205', Email = 'vikram.sethi' + EMAIL_DOMAIN, Description = TAG + 'Noida golf course belt and South Delhi.'));
med.put('sneha',   new Contact(AccountId = firm.Id, FirstName = 'Sneha',   LastName = 'Aggarwal',  Title = 'Property Advisor',        Phone = '0129-422-6640', MobilePhone = '+91-98991-45206', Email = 'sneha.aggarwal' + EMAIL_DOMAIN, Description = TAG + 'Greater Faridabad / Neharpar.'));
med.put('rahul',   new Contact(AccountId = firm.Id, FirstName = 'Rahul',   LastName = 'Chauhan',   Title = 'Property Advisor',        Phone = '0129-422-6641', MobilePhone = '+91-98188-45207', Email = 'rahul.chauhan' + EMAIL_DOMAIN, Description = TAG + 'Faridabad and Ballabgarh.'));
med.put('kavita',  new Contact(AccountId = firm.Id, FirstName = 'Kavita',  LastName = 'Rana',      Title = 'Senior Property Advisor', Phone = '011-4155-2202', MobilePhone = '+91-98105-45208', Email = 'kavita.rana' + EMAIL_DOMAIN, Description = TAG + 'South Delhi and Okhla.'));
med.put('deepak',  new Contact(AccountId = firm.Id, FirstName = 'Deepak',  LastName = 'Yadav',     Title = 'Property Advisor',        Phone = '0120-457-8822', MobilePhone = '+91-99538-45209', Email = 'deepak.yadav' + EMAIL_DOMAIN, Description = TAG + 'Greater Noida West.'));
med.put('farhan',  new Contact(AccountId = firm.Id, FirstName = 'Farhan',  LastName = 'Qureshi',   Title = 'Luxury Homes Specialist', Phone = '011-4155-2203', MobilePhone = '+91-98738-45210', Email = 'farhan.qureshi' + EMAIL_DOMAIN, Description = TAG + 'NCR-wide luxury inventory.'));
insert med.values();
System.debug('Inserted ' + med.size() + ' mediators.');

// ---------------------------------------------------------------- mediator <-> property
Map<String, List<String>> coverage = new Map<String, List<String>>{
    'camellias'     => new List<String>{ 'priya', 'farhan' },
    'm3mgolf'       => new List<String>{ 'priya', 'aman', 'farhan' },
    'aristocrat'    => new List<String>{ 'priya', 'aman' },
    'sobhacity'     => new List<String>{ 'aman', 'rohit' },
    'sigcity93'     => new List<String>{ 'aman', 'rahul' },
    'capgreens'     => new List<String>{ 'rohit', 'kavita' },
    'southestate'   => new List<String>{ 'kavita', 'vikram', 'farhan' },
    'tripundra'     => new List<String>{ 'rohit', 'farhan' },
    'amaryllis'     => new List<String>{ 'rohit', 'kavita', 'farhan' },
    'knightsbridge' => new List<String>{ 'vikram', 'farhan' },
    'godrejwoods'   => new List<String>{ 'neha', 'vikram' },
    'maxestates128' => new List<String>{ 'neha', 'vikram' },
    'county107'     => new List<String>{ 'neha', 'deepak' },
    'acedivino'     => new List<String>{ 'deepak', 'neha' },
    'amstoria'      => new List<String>{ 'sneha', 'rahul' },
    'omaxeheights'  => new List<String>{ 'sneha', 'rahul' },
    'rpssavana'     => new List<String>{ 'rahul', 'sneha' },
    'puriaravalis'  => new List<String>{ 'sneha', 'farhan' }
};
List<Mediator_Property__c> links = new List<Mediator_Property__c>();
for (String propKey : coverage.keySet()) {
    for (String medKey : coverage.get(propKey)) {
        links.add(new Mediator_Property__c(Property__c = props.get(propKey).Id, Mediator__c = med.get(medKey).Id));
    }
}
insert links;
System.debug('Inserted ' + links.size() + ' mediator-property links.');

// ---------------------------------------------------------------- a few booked slots
// Gives the availability action something real to work against: tomorrow 11:00-12:00
// two of the three M3M Golf Estate mediators are already out on a visit.
Datetime tomorrow11 = Datetime.newInstance(Date.today().addDays(1), Time.newInstance(11, 0, 0, 0));

List<Lead> visitors = new List<Lead>{
    new Lead(FirstName = 'Ankit', LastName = 'Gupta',  Company = 'Website Enquiry', Email = 'ankit.gupta' + EMAIL_DOMAIN,  Phone = '+91-98100-77001', LeadSource = 'Website Chatbot', Property_of_Interest__c = props.get('m3mgolf').Id,     Enquiry_Notes__c = TAG + 'Asked for a weekday morning site visit.'),
    new Lead(FirstName = 'Meera', LastName = 'Nair',   Company = 'Website Enquiry', Email = 'meera.nair' + EMAIL_DOMAIN,   Phone = '+91-98100-77002', LeadSource = 'Website Chatbot', Property_of_Interest__c = props.get('godrejwoods').Id, Enquiry_Notes__c = TAG + 'Comparing Sector 43 and Sector 128.'),
    new Lead(FirstName = 'Sameer', LastName = 'Bansal', Company = 'Website Enquiry', Email = 'sameer.bansal' + EMAIL_DOMAIN, Phone = '+91-98100-77003', LeadSource = 'Website Chatbot', Property_of_Interest__c = props.get('amstoria').Id,    Enquiry_Notes__c = TAG + 'Budget up to 2 Cr in Greater Faridabad.')
};
insert visitors;

insert new List<ServiceAppointment>{
    new ServiceAppointment(ParentRecordId = visitors[0].Id, Property__c = props.get('m3mgolf').Id, Mediator__c = med.get('priya').Id,
        Subject = 'Site visit - M3M Golf Estate', Status = 'Scheduled', SchedStartTime = tomorrow11, SchedEndTime = tomorrow11.addHours(1),
        Email = visitors[0].Email, Phone = visitors[0].Phone),
    new ServiceAppointment(ParentRecordId = visitors[0].Id, Property__c = props.get('m3mgolf').Id, Mediator__c = med.get('farhan').Id,
        Subject = 'Site visit - M3M Golf Estate', Status = 'Scheduled', SchedStartTime = tomorrow11.addMinutes(30), SchedEndTime = tomorrow11.addMinutes(90),
        Email = visitors[0].Email, Phone = visitors[0].Phone),
    new ServiceAppointment(ParentRecordId = visitors[1].Id, Property__c = props.get('godrejwoods').Id, Mediator__c = med.get('neha').Id,
        Subject = 'Site visit - Godrej Woods', Status = 'Scheduled', SchedStartTime = tomorrow11.addDays(1), SchedEndTime = tomorrow11.addDays(1).addHours(1),
        Email = visitors[1].Email, Phone = visitors[1].Phone),
    new ServiceAppointment(ParentRecordId = visitors[2].Id, Property__c = props.get('amstoria').Id, Mediator__c = med.get('sneha').Id,
        Subject = 'Site visit - BPTP Amstoria Verti-Greens', Status = 'Scheduled', SchedStartTime = tomorrow11.addDays(2), SchedEndTime = tomorrow11.addDays(2).addHours(1),
        Email = visitors[2].Email, Phone = visitors[2].Phone)
};

System.debug('DONE. Properties=' + [SELECT COUNT() FROM Property__c] +
             ' Specs=' + [SELECT COUNT() FROM Property_Specification__c] +
             ' Mediators=' + [SELECT COUNT() FROM Contact WHERE Email LIKE :('%' + EMAIL_DOMAIN)] +
             ' Links=' + [SELECT COUNT() FROM Mediator_Property__c] +
             ' SiteVisits=' + [SELECT COUNT() FROM ServiceAppointment]);
