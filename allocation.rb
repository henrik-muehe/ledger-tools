require 'json'
require 'date'
require 'open-uri'
require 'nokogiri'

# Determine symbols used in ledger.
symbols = `ledger reg --register-format '%(commodity)\n' | sort | uniq`.split

# Remove currencies.
symbols -= ["EURO", "$", "p$", "$p"]

# For each symbol, query morningstar for allocation data. If not available, use
# a simple heuristic to determine allocation.
symbols.each do |symbol|
  # Query morningstar.
  clean_symbol = symbol.gsub(/[^a-zA-Z0-9]/, "")
  doc = Nokogiri::HTML(open("http://portfolios.morningstar.com/fund/summary?t=#{clean_symbol}&region=usa&culture=en-US"))
  table = doc.xpath("//h3[contains(text(), 'Asset Allocation')]/following::tbody[1]")
  category =  doc.xpath("//*[contains(@class, 'categoryName')]/text()")
  rows = table.xpath(".//tr")
  allocation = {}
  rows.each do |row|
    cells = row.xpath(".//*/text()")
    next if cells.size == 0
    allocation[cells[0].to_s] = cells[1].to_s.to_f * 0.01
  end

  # Sum allocation.
  sum = allocation.values.reduce(:+)
  allocation = {} if sum == 0

  # Heuristic to determine allocation if none is available.
  if allocation.length == 0 then
    if category and not category.to_s.empty? and category.to_s.match(/bond/i) then
      allocation["Bond"] = 1.00
    else
      allocation["Stock"] = 1.00
    end
  end

  # Output allocation information in ledger format.
  puts "= expr ( commodity == '#{symbol}' and account =~ /^Assets:/ )"
  allocation.each do |type,ratio|
    parent_type = nil
    parent_type = "Stock" if type.match(/stock/i)
    parent_type = "Bond" if type.match(/bond/i)
    if parent_type and parent_type != type
      puts "    %-50s %1.4f" % ["(Allocation:#{parent_type}:#{type})", ratio]
    else
      puts "    %-50s %1.4f" % ["(Allocation:#{type})", ratio]
    end
  end
  puts
end
