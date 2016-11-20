require 'json'
require 'pp'
require 'date'
require 'open-uri'

# Load all commodity names from ledger.
raw = `ledger prices --prices-format '%a %(commodity)\n' --current | sort | uniq | tr -d '"'`

# Convert into hashmap.
symbols = raw.split("\n").map{|x| parts=x.split(" ", 2); { parts[0] => parts[1] } }.reduce(:merge)

# Hard-coded mapping of symbols. I use the exact same symbols to track things
# as Google Finance except for euros where I use an abbreviation. Also, I have
# a separate commodity called "pre-tax dollar" for which I have hardcoded the
# conversion (and therefore don't need to look it up here).
mapping = {
  "EURO" => "CURRENCY:EURUSD",
  "p$" => nil
}

# Remove everything mapping to nil.
symbols.delete_if{ |sym, cur| mapping.has_key?(sym) and mapping[sym].nil? }

# Remember unmapped symbols in the same order as the mapped symbols.
unmapped_lookup_symbols = symbols.keys

# Map all symbols.
lookup_symbols = unmapped_lookup_symbols.map{|sym| mapping.has_key?(sym) ? mapping[sym] : sym }.join(",")

# Load data from google finance.
data = open("http://finance.google.com/finance/info?client=ig&q=#{lookup_symbols}").read
data = data.gsub(/\/\//, "")  # Kill eval() guard.
data = JSON.parse(data)  # Parse to json.

# Ensure we were able to find all symbols. This is mostly so we don't silently
# forget to update any symbols.
raise "Can not resolve all stock symbols" if data.size != symbols.size

# Cache stringified date for today.
date = Time.now.strftime("%Y/%m/%d")

# Output price db entries.
puts
data.each_with_index do |data,index|
  unmapped_sym = unmapped_lookup_symbols[index]
  puts "P #{date} \"#{unmapped_sym}\" #{data["l"]} #{symbols[unmapped_sym]}"
end
