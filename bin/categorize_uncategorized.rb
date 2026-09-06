# frozen_string_literal: true
# Usage: bin/rails runner bin/categorize_uncategorized.rb

family = Family.find_by(name: "823 Spring Cove") || Family.first
puts "Target Family: #{family.name} (id: #{family.id})"

category_cache = {}
family.categories.each { |c| category_cache[c.name.downcase] = c }

merchant_cache = {}
family.merchants.each { |m| merchant_cache[m.name.downcase] = m }

def get_or_create_category(family, name, cache)
  return nil if name.blank?
  clean = name.strip
  cache[clean.downcase] ||= family.categories.find_or_create_by!(name: clean)
end

def get_or_create_merchant(family, name, cache)
  return nil if name.blank?
  clean = name.strip
  cache[clean.downcase] ||= family.merchants.find_or_create_by!(name: clean)
end

# Classification Ruleset (ordered regex / pattern matching)
RULES = [
  # Payroll & Inflow
  { pattern: /MCMASTER.*PAYROLL/i, category: "Income: Payroll", merchant: "McMaster-Carr" },
  { pattern: /BANK INT|INTEREST PAID/i, category: "Income: Interest", merchant: "Bank Interest" },
  { pattern: /ILSTTAXRFD|STATE OF ILL/i, category: "Income: Reimbursements", merchant: "State of Illinois" },
  { pattern: /UNITED HEALTHCAR.*PAYMNT/i, category: "Income: Reimbursements", merchant: "UnitedHealthcare" },
  { pattern: /ATM REIMBURSEMENT/i, category: "Income: Reimbursements", merchant: "ATM Fee Reimbursement" },

  # Internal Transfers & Credit Card / Loan Payments
  { pattern: /CHASE CREDIT CRD AUTOPAY|AUTOMATIC PAYMENT - THANK/i, category: "Credit Card Payment", merchant: "Chase Credit Card" },
  { pattern: /Requested transfer from ALLY BANK/i, category: "Transfer: Internal", merchant: "Ally Bank" },
  { pattern: /JPMORGAN CHASE CHASE ACH|PAYMENT.*MORTGAGE/i, category: "Home Repair / Reno", merchant: "Chase Mortgage" },

  # Childcare & Education
  { pattern: /THE GODDARD SCHO/i, category: "Education & Childcare", merchant: "The Goddard School" },
  { pattern: /BRIDGET PILEGGI/i, category: "Education & Childcare", merchant: "Bridget Pileggi" },
  { pattern: /LEARNING EXPRESS/i, category: "Education & Childcare", merchant: "Learning Express Toys" },

  # Pet
  { pattern: /Pals For Pups/i, category: "Pet: Riley", merchant: "Pals for Pups" },
  { pattern: /BARK ABOUT IT/i, category: "Pet: Riley", merchant: "Bark About It!" },
  { pattern: /CHWYINC|CHEWY/i, category: "Pet: Riley", merchant: "Chewy" },
  { pattern: /GOLFROSE/i, category: "Pet: Riley", merchant: "Golf Rose Animal Hospital" },

  # Home Cleaning / Maintenance
  { pattern: /Seka \(Cleaner\)|Seka \(CLEANER\)/i, category: "Home Repair / Reno", merchant: "Seka Cleaning" },
  { pattern: /Vanya/i, category: "Home Repair / Reno", merchant: "Vanya Cleaning" },
  { pattern: /COOK COUNTY SINGLE PRO/i, category: "Legal & Taxes", merchant: "Cook County Treasurer" },
  { pattern: /VOSchaumburg UTLPAYMENT|VILLAGE OF SCHAUMBURG/i, category: "Utilities: Water", merchant: "Village of Schaumburg" },

  # Utilities
  { pattern: /NICOR GAS/i, category: "Utilities: Gas", merchant: "Nicor Gas" },
  { pattern: /COMED/i, category: "Utilities: Electric", merchant: "ComEd" },
  { pattern: /VERIZON/i, category: "Utilities: Cell Phone", merchant: "Verizon Wireless" },
  { pattern: /AT&T/i, category: "Utilities: Cell Phone", merchant: "AT&T" },
  { pattern: /COMCAST|XFINITY/i, category: "Utilities: Internet", merchant: "Comcast Xfinity" },
  { pattern: /GOOGLE \*Google One|Google One/i, category: "Utilities: Internet", merchant: "Google One" },
  { pattern: /CLOUDFLARE/i, category: "Utilities: Internet", merchant: "Cloudflare" },
  { pattern: /SIMPLEFIN BRIDGE/i, category: "Utilities: Internet", merchant: "SimpleFIN Bridge" },

  # Groceries
  { pattern: /JEWEL OSCO/i, category: "Groceries", merchant: "Jewel-Osco" },
  { pattern: /COSTCO/i, category: "Groceries", merchant: "Costco" },
  { pattern: /MARIANOS/i, category: "Groceries", merchant: "Mariano's" },
  { pattern: /ALDI/i, category: "Groceries", merchant: "ALDI" },
  { pattern: /TRADER JOE/i, category: "Groceries", merchant: "Trader Joe's" },
  { pattern: /WHOLEFDS|WHOLE FOODS/i, category: "Groceries", merchant: "Whole Foods" },

  # Dining & Fast Food
  { pattern: /ARAMARK MCMASTER CARR/i, category: "Dining Out", merchant: "McMaster-Carr Cafeteria" },
  { pattern: /MCDONALD'?S/i, category: "Dining Out", merchant: "McDonald's" },
  { pattern: /TACO BELL/i, category: "Dining Out", merchant: "Taco Bell" },
  { pattern: /BURGER KING/i, category: "Dining Out", merchant: "Burger King" },
  { pattern: /WENDY'?S/i, category: "Dining Out", merchant: "Wendy's" },
  { pattern: /PORTILLO'?S/i, category: "Dining Out", merchant: "Portillo's" },
  { pattern: /CHIPOTLE/i, category: "Dining Out", merchant: "Chipotle" },
  { pattern: /PANDA EXPRESS/i, category: "Dining Out", merchant: "Panda Express" },
  { pattern: /DOORDASH/i, category: "Dining Out", merchant: "DoorDash" },
  { pattern: /UBER EATS/i, category: "Dining Out", merchant: "Uber Eats" },
  { pattern: /ROSATIS/i, category: "Dining Out", merchant: "Rosati's Pizza" },
  { pattern: /EGG HARBOR/i, category: "Dining Out", merchant: "Egg Harbor Cafe" },
  { pattern: /EGGTUCK/i, category: "Dining Out", merchant: "Eggtuck" },
  { pattern: /OLIVE GARDEN/i, category: "Dining Out", merchant: "Olive Garden" },
  { pattern: /NOTHING BUNDT CAKES/i, category: "Dining Out", merchant: "Nothing Bundt Cakes" },
  { pattern: /SPRINKLES ICE CREAM/i, category: "Dining Out", merchant: "Sprinkles Ice Cream" },
  { pattern: /SWEET ORANGE PANCAKES/i, category: "Dining Out", merchant: "Sweet Orange Pancakes" },
  { pattern: /WING SNOB/i, category: "Dining Out", merchant: "Wing Snob" },
  { pattern: /MORE BREWING/i, category: "Dining Out", merchant: "More Brewing" },
  { pattern: /BARREL HOUSE SOCIAL/i, category: "Dining Out", merchant: "Barrel House Social" },
  { pattern: /BRINY SWINE/i, category: "Dining Out", merchant: "Briny Swine Smokehouse" },
  { pattern: /CHI TEA/i, category: "Dining Out", merchant: "Chi Tea" },
  { pattern: /BEER ON THE WALL/i, category: "Dining Out", merchant: "Beer on the Wall" },
  { pattern: /PINTS/i, category: "Dining Out", merchant: "Pints" },
  { pattern: /TREX ORLANDO RESTAURAN/i, category: "Dining Out", merchant: "T-Rex Cafe" },

  # Travel & Lodging & Entertainment
  { pattern: /WDW|WALT DISNEY WORLD/i, category: "Travel & Lodging", merchant: "Walt Disney World" },
  { pattern: /SHEDD AQUARIUM/i, category: "Entertainment & Hobbies", merchant: "Shedd Aquarium" },
  { pattern: /AMC \d+/i, category: "Entertainment & Hobbies", merchant: "AMC Theatres" },
  { pattern: /Bumble Dating/i, category: "Entertainment & Hobbies", merchant: "Bumble" },
  { pattern: /YOUTUBEPREMIUM|YouTubePremium/i, category: "Entertainment & Hobbies", merchant: "YouTube Premium" },
  { pattern: /MARQUEE SPORTS/i, category: "Entertainment & Hobbies", merchant: "Marquee Sports Network" },
  { pattern: /PATREON/i, category: "Entertainment & Hobbies", merchant: "Patreon" },
  { pattern: /MICROSOFT\*XBOX|XBOX/i, category: "Entertainment & Hobbies", merchant: "Microsoft Xbox" },
  { pattern: /NEWSDEMON/i, category: "Entertainment & Hobbies", merchant: "Newsdemon" },
  { pattern: /ALLDEBRID/i, category: "Entertainment & Hobbies", merchant: "Alldebrid" },
  { pattern: /RING AI PRO PLAN/i, category: "Home Repair / Reno", merchant: "Ring" },

  # Transportation & Parking & Gas
  { pattern: /PARK CHICAGO/i, category: "Transportation", merchant: "ParkChicago" },
  { pattern: /METROPOLIS PARKING/i, category: "Transportation", merchant: "Metropolis Parking" },
  { pattern: /SOLDIER FIELD NORTH GARA/i, category: "Transportation", merchant: "Soldier Field Parking" },
  { pattern: /GEM CAR WASH|H2O CARWASH/i, category: "Transportation", merchant: "Car Wash" },
  { pattern: /EXXON BUCKY'?S|BUCKY'?S/i, category: "Transportation", merchant: "Bucky's Express" },
  { pattern: /7-ELEVEN/i, category: "Transportation", merchant: "7-Eleven" },

  # Healthcare & Dental
  { pattern: /ALL ABOUT KIDS DENTISTRY/i, category: "Healthcare & Medical", merchant: "All About Kids Dentistry" },
  { pattern: /ALEXIAN BROTHERS/i, category: "Healthcare & Medical", merchant: "Alexian Brothers Medical" },
  { pattern: /SCHWARTZ PEDIATRICS/i, category: "Healthcare & Medical", merchant: "Schwartz Pediatrics" },
  { pattern: /SCHAUMBURG DENTAL/i, category: "Healthcare & Medical", merchant: "Schaumburg Dental Studio" },
  { pattern: /NCH MY CHART|NORTHWEST COMMUNITY/i, category: "Healthcare & Medical", merchant: "Northwest Community Healthcare" },
  { pattern: /SUBURBAN ASSOCIATES/i, category: "Healthcare & Medical", merchant: "Suburban Associates" },

  # Personal Care & Shopping
  { pattern: /KIDSNIPS/i, category: "Personal Care", merchant: "Kidsnips" },
  { pattern: /LUSH WOODFIELD/i, category: "Personal Care", merchant: "Lush Cosmetics" },
  { pattern: /AMAZON|AMZN|Amazon\.com/i, category: "Shopping", merchant: "Amazon" },
  { pattern: /WAL-?MART|WM SUPERCENTER/i, category: "Shopping", merchant: "Walmart" },
  { pattern: /TARGET/i, category: "Shopping", merchant: "Target" },
  { pattern: /IKEA/i, category: "Shopping", merchant: "Ikea" },
  { pattern: /BEST BUY/i, category: "Shopping", merchant: "Best Buy" },
  { pattern: /DICK'?S SPORTING/i, category: "Shopping", merchant: "Dick's Sporting Goods" },
  { pattern: /OLD NAVY/i, category: "Shopping", merchant: "Old Navy" },
  { pattern: /UNIQLO/i, category: "Shopping", merchant: "Uniqlo" },
  { pattern: /JOURNEYS KIDZ/i, category: "Shopping", merchant: "Journeys Kidz" },
  { pattern: /MCMASTER-CARR(?!.*PAYROLL)/i, category: "Shopping", merchant: "McMaster-Carr Supply" },

  # Zelle Transfers
  { pattern: /Zelle payment from/i, category: "Zelle Incoming", merchant: "Zelle" },
  { pattern: /Zelle payment to/i, category: "Zelle Outgoing", merchant: "Zelle" },
  { pattern: /Zelle transfer/i, category: "Zelle Incoming", merchant: "Zelle" },

  # Tolls & Parking & Gas
  { pattern: /IL TOLLWAY/i, category: "Transportation", merchant: "Illinois Tollway" },
  { pattern: /SPOTHERO/i, category: "Transportation", merchant: "SpotHero" },
  { pattern: /SHELL|EXXON REBEL|BP#|MOBIL/i, category: "Transportation", merchant: "Gas Station" },

  # Additional Dining
  { pattern: /BUDDYS SCHAUMBURG/i, category: "Dining Out", merchant: "Buddy's Schaumburg" },
  { pattern: /JIMMY JOHN'?S/i, category: "Dining Out", merchant: "Jimmy John's" },
  { pattern: /DANTHAI/i, category: "Dining Out", merchant: "Danthai Food" },

  # Additional Pet
  { pattern: /COMB & COLLAR/i, category: "Pet: Riley", merchant: "Comb & Collar Club" },

  # Additional Childcare & Kids
  { pattern: /LAVA ISLAND/i, category: "Education & Childcare", merchant: "Lava Island" },

  # Software & Services
  { pattern: /OPENROUTER/i, category: "Utilities: Internet", merchant: "OpenRouter" },
  { pattern: /GITHUB/i, category: "Utilities: Internet", merchant: "GitHub" },

  # Advisory & Investments
  { pattern: /MGMTFEE TO ADVISOR/i, category: "Legal & Taxes", merchant: "Financial Advisor Fee" },
  { pattern: /PAYMENT.*MORTGAGE|Payment - PAYMENT/i, category: "Home Repair / Reno", merchant: "Mortgage Payment" },

  # Additional Shopping & Tech
  { pattern: /THE HOME DEPOT|HOME DEPOT/i, category: "Home Repair / Reno", merchant: "The Home Depot" },
  { pattern: /MICRO CENTER/i, category: "Shopping", merchant: "Micro Center" },
  { pattern: /HANNA ANDERSSON/i, category: "Shopping", merchant: "Hanna Andersson" },
  { pattern: /LITTLE GREEN APPLE/i, category: "Shopping", merchant: "Little Green Apple" },
  { pattern: /IT'?SUGAR/i, category: "Shopping", merchant: "IT'SUGAR" },

  # Additional Transportation
  { pattern: /UBER\s*\*TRIP|UBER/i, category: "Transportation", merchant: "Uber" },
  { pattern: /THORNTONS/i, category: "Transportation", merchant: "Thorntons Gas" },
  { pattern: /MERIE TRANSPORTATION/i, category: "Transportation", merchant: "Merie Transportation" },

  # Additional Software / Tech / Entertainment
  { pattern: /MICROSOFT/i, category: "Utilities: Internet", merchant: "Microsoft" },
  { pattern: /NVIDIA/i, category: "Shopping", merchant: "Nvidia" },
  { pattern: /STEAMGAMES|STEAM/i, category: "Entertainment & Hobbies", merchant: "Steam" },
  { pattern: /THECUBENET/i, category: "Entertainment & Hobbies", merchant: "The Cube Net" },
  { pattern: /GALAXY SCHAUMBURG/i, category: "Entertainment & Hobbies", merchant: "Galaxy Schaumburg" },
  { pattern: /SIM RACING/i, category: "Entertainment & Hobbies", merchant: "Sim Racing" },
  { pattern: /PLAYSTACK|PLAYSTATION/i, category: "Entertainment & Hobbies", merchant: "PlayStation" },
  { pattern: /GOOGLE \*CLOUD/i, category: "Utilities: Internet", merchant: "Google Cloud" },

  # Additional Medical & Health
  { pattern: /HIMS & HERS/i, category: "Healthcare & Medical", merchant: "Hims & Hers" },
  { pattern: /EYEBOUTIQUE/i, category: "Healthcare & Medical", merchant: "Eye Boutique" },

  # Taxes, Bank Fees, Transfers
  { pattern: /IRS USATAXPYMT|IRS/i, category: "Legal & Taxes", merchant: "IRS" },
  { pattern: /ANNUAL MEMBERSHIP FEE/i, category: "Legal & Taxes", merchant: "Credit Card Annual Fee" },
  { pattern: /Internet transfer from Spending account/i, category: "Transfer: Internal", merchant: "Ally Bank" },
  { pattern: /REMOTE ONLINE DEPOSIT/i, category: "Income: Reimbursements", merchant: "Check Deposit" },

  # Additional Dining & Coffee
  { pattern: /STARBUCKS/i, category: "Dining Out", merchant: "Starbucks" },
  { pattern: /CULVER'?S/i, category: "Dining Out", merchant: "Culver's" },
  { pattern: /DUNKIN/i, category: "Dining Out", merchant: "Dunkin'" },
  { pattern: /JOE'?S PIZZA/i, category: "Dining Out", merchant: "Joe's Pizza" },
  { pattern: /BIBIBOP/i, category: "Dining Out", merchant: "Bibibop" },
  { pattern: /SMALL CHEVAL/i, category: "Dining Out", merchant: "Small Cheval" },
  { pattern: /FADO IRISH PUB/i, category: "Dining Out", merchant: "Fado Irish Pub" },
  { pattern: /PALMER PLACE/i, category: "Dining Out", merchant: "Palmer Place" },
  { pattern: /CANTEEN VENDING/i, category: "Dining Out", merchant: "Canteen Vending" },
  { pattern: /POTBELLY/i, category: "Dining Out", merchant: "Potbelly" },
  { pattern: /P\.?F\.?\s*CHANG'?S/i, category: "Dining Out", merchant: "P.F. Chang's" },
  { pattern: /CIELO MEXICAN/i, category: "Dining Out", merchant: "Cielo Mexican Grill" },
  { pattern: /MAXFIELDS/i, category: "Dining Out", merchant: "Maxfields Restaurant" },
  { pattern: /GREAT AMERICAN BAGEL/i, category: "Dining Out", merchant: "Great American Bagel" },
  { pattern: /BREWPOINTCOFFEE/i, category: "Dining Out", merchant: "Brewpoint Coffee" },
  { pattern: /TST\*|SQ \*/i, category: "Dining Out", merchant: "Local Restaurant / Cafe" },

  # Charity, Gifts & Miscellaneous
  { pattern: /OXFAM/i, category: "Shopping", merchant: "Oxfam America" },
  { pattern: /EXTRA VALUE WINE/i, category: "Dining Out", merchant: "Extra Value Wine & Spirits" },
  { pattern: /HARDROCK SMOKE/i, category: "Personal Care", merchant: "Hardrock Smoke and Vape" },
  { pattern: /QUICKTAG/i, category: "Pet: Riley", merchant: "QuickTag" },
  { pattern: /GENEVA FESTIVALS/i, category: "Entertainment & Hobbies", merchant: "Geneva Festivals" },
  { pattern: /HOUSE OF SPORT/i, category: "Shopping", merchant: "House of Sport" },
  { pattern: /LDC CHICAGO|CHICAGOLAND|T&D HOKKAI|AMZ\*|SYLWM|CAPTURED CREATIONS/i, category: "Shopping", merchant: "Retail / Entertainment" },

  # Additional Shopping
  { pattern: /MACY'?S/i, category: "Shopping", merchant: "Macy's" },
  { pattern: /NEVER ENDING CYCLES/i, category: "Entertainment & Hobbies", merchant: "Never Ending Cycles" },

  # Investments & Institutional Fund Activity (in IRA / Brokerage)
  { pattern: /PGIM TOTAL RETURN BOND|PGIM HIGH YIELD|WEITZ CORE PLUS|SCHWAB PRIME ADVANTAGE|US TREASU NT/i, category: "Investment Contributions", merchant: "Institutional Fund" }
]

uncategorized_txs = family.transactions
  .where(category_id: nil)
  .includes(:entry)

puts "Found #{uncategorized_txs.count} uncategorized transactions to evaluate."

updated_count = 0
unmatched = []

uncategorized_txs.find_each do |tx|
  entry_name = tx.entry&.name || ""
  matched_rule = RULES.find { |r| entry_name =~ r[:pattern] }

  if matched_rule
    cat = get_or_create_category(family, matched_rule[:category], category_cache)
    merch = get_or_create_merchant(family, matched_rule[:merchant], merchant_cache)
    tx.update!(category: cat, merchant: merch)
    updated_count += 1
  else
    unmatched << entry_name
  end
end

puts "Successfully categorized #{updated_count} transactions!"
puts "Remaining uncategorized: #{unmatched.size}"

if unmatched.any?
  puts "Remaining unmatched sample (top 15):"
  counts = Hash.new(0)
  unmatched.each { |name| counts[name] += 1 }
  counts.sort_by { |_, count| -count }.first(15).each do |name, count|
    puts "  [#{count}x] #{name}"
  end
end
