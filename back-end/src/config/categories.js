// Matches the expense_category enum (000_extensions_enums.sql). Kept as a
// plain list here (rather than querying pg_enum) so the keyword/embedding
// layers below can reference it without a DB round-trip.
const CATEGORIES = [
  'food_dining',
  'transport',
  'shopping',
  'groceries',
  'entertainment',
  'health_medical',
  'utilities',
  'education',
  'travel',
  'personal_care',
  'subscription',
  'investment',
  'other',
];

// One short descriptive sentence per category — embedded once at startup
// and compared against incoming merchant text via cosine similarity when
// the keyword pass below doesn't match. Edit freely; no code changes
// needed elsewhere to add/adjust a description.
const CATEGORY_DESCRIPTIONS = {
  food_dining: 'Restaurants, cafes, coffee shops, fast food and dining out.',
  transport: 'Ride-hailing, tolls, fuel, parking, public transit and taxis.',
  shopping: 'Retail stores, online marketplaces, clothing and general merchandise.',
  groceries: 'Supermarkets, grocery stores and convenience stores for household food.',
  entertainment: 'Movies, cinemas, games, streaming and leisure activities.',
  health_medical: 'Pharmacies, clinics, hospitals and medical treatment.',
  utilities: 'Electricity, water, internet, mobile and telecom bills.',
  education: 'Tuition, bookstores, courses and school-related expenses.',
  travel: 'Flights, hotels, travel agencies and holiday bookings.',
  personal_care: 'Salons, barbers, spas and personal grooming.',
  subscription: 'Recurring digital subscriptions like streaming or cloud storage plans.',
  investment: 'Stock trading, unit trusts, crypto and savings investment platforms.',
  other: 'Miscellaneous purchases that do not fit another category.',
};

// Mock starter dictionary: normalized merchant keyword -> category. Checked
// as a substring match against the normalized merchant text (see
// categorization.service.js). Keep entries lowercase with no punctuation,
// since that's the form normalizeMerchantText() produces. Add more entries
// here as real merchant data comes in — no other file needs to change.
const KEYWORD_MAP = {
  // food_dining
  starbucks: 'food_dining',
  mcdonald: 'food_dining',
  kfc: 'food_dining',
  'pizza hut': 'food_dining',
  subway: 'food_dining',
  dominos: 'food_dining',
  chatime: 'food_dining',
  'secret recipe': 'food_dining',
  'old town': 'food_dining',
  'texas chicken': 'food_dining',
  restoran: 'food_dining',
  cafe: 'food_dining',
  kopitiam: 'food_dining',

  // transport
  grab: 'transport',
  'touch n go': 'transport',
  tng: 'transport',
  ktm: 'transport',
  rapidkl: 'transport',
  mrt: 'transport',
  lrt: 'transport',
  petronas: 'transport',
  shell: 'transport',
  caltex: 'transport',
  parking: 'transport',

  // shopping
  shopee: 'shopping',
  lazada: 'shopping',
  uniqlo: 'shopping',
  zara: 'shopping',
  ikea: 'shopping',
  aeon: 'shopping',
  watson: 'shopping',
  padini: 'shopping',

  // groceries
  tesco: 'groceries',
  giant: 'groceries',
  mydin: 'groceries',
  'jaya grocer': 'groceries',
  'village grocer': 'groceries',
  '99 speedmart': 'groceries',
  'kk mart': 'groceries',
  lotus: 'groceries',

  // entertainment
  gsc: 'entertainment',
  tgv: 'entertainment',
  cinema: 'entertainment',
  steam: 'entertainment',
  astro: 'entertainment',

  // health_medical
  guardian: 'health_medical',
  caring: 'health_medical',
  klinik: 'health_medical',
  clinic: 'health_medical',
  hospital: 'health_medical',
  pharmacy: 'health_medical',

  // utilities
  tnb: 'utilities',
  syabas: 'utilities',
  'air selangor': 'utilities',
  unifi: 'utilities',
  maxis: 'utilities',
  celcom: 'utilities',
  digi: 'utilities',
  hotlink: 'utilities',

  // education
  tuition: 'education',
  'popular bookstore': 'education',
  mph: 'education',
  udemy: 'education',
  coursera: 'education',

  // travel
  airasia: 'travel',
  'malaysia airlines': 'travel',
  agoda: 'travel',
  'booking com': 'travel',
  klia: 'travel',
  hotel: 'travel',

  // personal_care
  salon: 'personal_care',
  barber: 'personal_care',
  spa: 'personal_care',
  sephora: 'personal_care',

  // subscription
  netflix: 'subscription',
  spotify: 'subscription',
  'disney plus': 'subscription',
  'youtube premium': 'subscription',
  'icloud': 'subscription',

  // investment
  'rakuten trade': 'investment',
  stashaway: 'investment',
  luno: 'investment',
  asnb: 'investment',
};

module.exports = { CATEGORIES, CATEGORY_DESCRIPTIONS, KEYWORD_MAP };
