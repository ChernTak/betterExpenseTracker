// Mirrors the expense_category enum; kept as a plain list so keyword/embedding matching below can use it without a DB round-trip.
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

// One sentence per category, embedded at startup and compared via cosine similarity when the keyword pass below doesn't match.
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

// Mock starter dictionary: normalized merchant keyword -> category, substring-matched against normalizeMerchantText() output (lowercase, no punctuation).
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

// Seeded as each user's default categories at signup; `other` is protected since category deletes reassign expenses to it.
const DEFAULT_CATEGORIES = [
  { key: 'food_dining', label: 'Food Dining', icon: 'restaurant', color: '#E58A3B' },
  { key: 'transport', label: 'Transport', icon: 'directions_bus', color: '#3B82C4' },
  { key: 'shopping', label: 'Shopping', icon: 'shopping_bag', color: '#9B59B6' },
  { key: 'groceries', label: 'Groceries', icon: 'local_grocery_store', color: '#2FA84F' },
  { key: 'entertainment', label: 'Entertainment', icon: 'movie', color: '#D64545' },
  { key: 'health_medical', label: 'Health Medical', icon: 'medical_services', color: '#35A79C' },
  { key: 'utilities', label: 'Utilities', icon: 'bolt', color: '#B8860B' },
  { key: 'education', label: 'Education', icon: 'school', color: '#4C6EF5' },
  { key: 'travel', label: 'Travel', icon: 'flight', color: '#00A8A8' },
  { key: 'personal_care', label: 'Personal Care', icon: 'spa', color: '#E066A6' },
  { key: 'subscription', label: 'Subscription', icon: 'subscriptions', color: '#7C6EF5' },
  { key: 'investment', label: 'Investment', icon: 'trending_up', color: '#12463A' },
  { key: 'other', label: 'Other', icon: 'receipt_long', color: '#8B8F97', isProtected: true },
];

// Must match the frontend's kCategoryIconPresets keys exactly, or a category could be saved with an icon key the app can't render.
const ICON_PRESET_KEYS = [
  'restaurant', 'directions_bus', 'shopping_bag', 'local_grocery_store', 'movie',
  'medical_services', 'bolt', 'school', 'flight', 'spa', 'subscriptions', 'trending_up',
  'receipt_long', 'pets', 'home', 'fitness_center', 'card_giftcard', 'directions_car',
  'local_cafe', 'phone_android', 'child_care', 'sports_esports', 'savings', 'checkroom',
  'build', 'pool', 'local_bar', 'cake', 'park', 'work', 'favorite', 'star', 'category',
];

// Same idea as ICON_PRESET_KEYS, for the color swatch grid.
const COLOR_PRESETS = [
  '#E58A3B', '#3B82C4', '#9B59B6', '#2FA84F', '#D64545', '#35A79C', '#B8860B',
  '#4C6EF5', '#00A8A8', '#E066A6', '#7C6EF5', '#12463A', '#8B8F97', '#FF6F61',
  '#6B8E23', '#C2185B', '#009688', '#5D4037', '#455A64', '#FFA000',
];

module.exports = {
  CATEGORIES,
  CATEGORY_DESCRIPTIONS,
  KEYWORD_MAP,
  DEFAULT_CATEGORIES,
  ICON_PRESET_KEYS,
  COLOR_PRESETS,
};
