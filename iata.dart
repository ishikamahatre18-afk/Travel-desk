/// Nearest commercial airport code for each built-in place.
/// Used to label fare results (and by live fare providers).
const kIata = <String, String>{
  // India
  'Delhi': 'DEL', 'Mumbai': 'BOM', 'Bengaluru': 'BLR', 'Chennai': 'MAA',
  'Kolkata': 'CCU', 'Hyderabad': 'HYD', 'Pune': 'PNQ', 'Ahmedabad': 'AMD',
  'Jaipur': 'JAI', 'Goa': 'GOI', 'Indore': 'IDR', 'Bhopal': 'BHO',
  'Lucknow': 'LKO', 'Kanpur': 'KNU', 'Nagpur': 'NAG', 'Surat': 'STV',
  'Vadodara': 'BDQ', 'Rajkot': 'RAJ', 'Chandigarh': 'IXC', 'Amritsar': 'ATQ',
  'Ludhiana': 'LUH', 'Jodhpur': 'JDH', 'Udaipur': 'UDR', 'Jaisalmer': 'JSA',
  'Pushkar': 'KQH', 'Agra': 'AGR', 'Varanasi': 'VNS', 'Prayagraj': 'IXD',
  'Patna': 'PAT', 'Ranchi': 'IXR', 'Bhubaneswar': 'BBI', 'Puri': 'BBI',
  'Visakhapatnam': 'VTZ', 'Vijayawada': 'VGA', 'Tirupati': 'TIR',
  'Coimbatore': 'CJB', 'Madurai': 'IXM', 'Kochi': 'COK',
  'Thiruvananthapuram': 'TRV', 'Munnar': 'COK', 'Alleppey': 'COK',
  'Mysuru': 'MYQ', 'Ooty': 'CJB', 'Pondicherry': 'PNY', 'Mangaluru': 'IXE',
  'Guwahati': 'GAU', 'Shillong': 'SHL', 'Gangtok': 'PYG', 'Darjeeling': 'IXB',
  'Srinagar': 'SXR', 'Leh': 'IXL', 'Jammu': 'IXJ', 'Shimla': 'SLV',
  'Manali': 'KUU', 'Dharamshala': 'DHM', 'Dehradun': 'DED', 'Rishikesh': 'DED',
  'Haridwar': 'DED', 'Nainital': 'PGH', 'Port Blair': 'IXZ', 'Raipur': 'RPR',
  'Gwalior': 'GWL', 'Jabalpur': 'JLR', 'Ujjain': 'IDR', 'Aurangabad': 'IXU',
  'Nashik': 'ISK', 'Kolhapur': 'KLH',
  // Asia, Middle East
  'Dubai': 'DXB', 'Abu Dhabi': 'AUH', 'Doha': 'DOH', 'Muscat': 'MCT',
  'Istanbul': 'IST', 'Singapore': 'SIN', 'Kuala Lumpur': 'KUL',
  'Langkawi': 'LGK', 'Bangkok': 'BKK', 'Phuket': 'HKT', 'Pattaya': 'UTP',
  'Krabi': 'KBV', 'Bali': 'DPS', 'Jakarta': 'CGK', 'Hanoi': 'HAN',
  'Ho Chi Minh City': 'SGN', 'Da Nang': 'DAD', 'Siem Reap': 'REP',
  'Manila': 'MNL', 'Colombo': 'CMB', 'Kandy': 'CMB', 'Maldives': 'MLE',
  'Kathmandu': 'KTM', 'Pokhara': 'PKR', 'Thimphu': 'PBH', 'Paro': 'PBH',
  'Dhaka': 'DAC', 'Hong Kong': 'HKG', 'Macau': 'MFM', 'Tokyo': 'HND',
  'Osaka': 'KIX', 'Seoul': 'ICN', 'Beijing': 'PEK', 'Shanghai': 'PVG',
  'Taipei': 'TPE', 'Tbilisi': 'TBS', 'Baku': 'GYD', 'Almaty': 'ALA',
  'Tashkent': 'TAS',
  // Africa
  'Cairo': 'CAI', 'Nairobi': 'NBO', 'Cape Town': 'CPT', 'Johannesburg': 'JNB',
  'Mauritius': 'MRU', 'Seychelles': 'SEZ',
  // Europe
  'London': 'LHR', 'Edinburgh': 'EDI', 'Dublin': 'DUB', 'Paris': 'CDG',
  'Rome': 'FCO', 'Milan': 'MXP', 'Venice': 'VCE', 'Barcelona': 'BCN',
  'Madrid': 'MAD', 'Lisbon': 'LIS', 'Amsterdam': 'AMS', 'Zurich': 'ZRH',
  'Interlaken': 'ZRH', 'Vienna': 'VIE', 'Prague': 'PRG', 'Budapest': 'BUD',
  'Berlin': 'BER', 'Munich': 'MUC', 'Athens': 'ATH', 'Santorini': 'JTR',
  'Copenhagen': 'CPH', 'Stockholm': 'ARN', 'Oslo': 'OSL', 'Helsinki': 'HEL',
  'Moscow': 'SVO',
  // Americas, Oceania
  'New York': 'JFK', 'Los Angeles': 'LAX', 'San Francisco': 'SFO',
  'Las Vegas': 'LAS', 'Chicago': 'ORD', 'Toronto': 'YYZ', 'Vancouver': 'YVR',
  'Sydney': 'SYD', 'Melbourne': 'MEL', 'Auckland': 'AKL',
};

String airportFor(String city) => kIata[city] ?? city;
