require "open-uri"
require "nokogiri"
require "json"
require "time"

module Zonneplan
  PRICE_DIVISOR = 100_000
  ENERGYZERO_MULTIPLIER = 10_000_000
  ENERGY_TAX_RAW = 1_108_481
  HANDLING_FEE_RAW = 200_000

  module_function

  def classify_pricing_profile(price, all_prices)
    sorted = all_prices.sort
    q1 = sorted[(sorted.length * 0.25).floor]
    q3 = sorted[(sorted.length * 0.75).floor]

    if price <= q1
      "low"
    elsif price >= q3
      "high"
    else
      "normal"
    end
  end

  def convert_energyzero_price(price_eur)
    (price_eur * ENERGYZERO_MULTIPLIER).round
  end

  def display_price(raw_price)
    (raw_price.to_f / PRICE_DIVISOR).round(0)
  end

  def fetch_from_zonneplan(user_agent)
    url = "https://www.zonneplan.nl/energie/dynamische-energieprijzen"
    html = URI.open(url, "User-Agent" => user_agent).read

    entries = parse_price_entries(html)
    if entries.nil?
      $stderr.puts "Electricity price entries not found on Zonneplan page."
      return nil
    end

    $stderr.puts "Fetched #{entries.length} price entries from Zonneplan."
    entries
  end

  # The page streams its React Flight payload through self.__next_f.push([n, "<json>"]).
  # The electricity block carries a 15-minute "quarters" array next to the 60-minute
  # "hours" array; quarters win. Entries used to be tagged "__typename":"ElectricityHour",
  # which the site dropped — the array key is the anchor now.
  def parse_price_entries(html)
    html.scan(/self\.__next_f\.push\(\[\d+,\s*"((?:[^"\\]|\\.)*)"\]\)/) do |(payload)|
      next unless payload.include?("priceTotalTaxIncluded")
      decoded = JSON.parse(%Q{"#{payload}"})
      entries = extract_price_entries(decoded, "quarters") || extract_price_entries(decoded, "hours")
      return entries if entries
    end
    nil
  end

  # Entries are flat objects, so the first "]" after the opening bracket closes the array.
  # A Flight payload may serialise the field as a reference ("quarters":"$L52") instead of
  # an array; every non-array shape must fall through to the next key, never raise.
  def extract_price_entries(text, key)
    marker = %Q{"#{key}":[}
    start = text.index(marker)
    return nil unless start
    open_bracket = start + marker.length - 1
    close_bracket = text.index("]", open_bracket)
    return nil unless close_bracket
    entries = JSON.parse(text[open_bracket..close_bracket])
    return nil unless entries.is_a?(Array) && !entries.empty?
    return nil unless entries.all? { _1.is_a?(Hash) && _1.key?("priceTotalTaxIncluded") }
    entries
  rescue JSON::ParserError
    nil
  end

  def fetch_from_energyzero(user_agent)
    now = Time.now.localtime
    from_date = Time.new(now.year, now.month, now.day, 0, 0, 0, now.utc_offset)
    till_date = from_date + (2 * 24 * 3600) - 1

    from_utc = from_date.utc.strftime("%Y-%m-%dT%H:%M:%S.000Z")
    till_utc = till_date.utc.strftime("%Y-%m-%dT%H:%M:%S.999Z")

    api_url = "https://api.energyzero.nl/v1/energyprices?fromDate=#{from_utc}&tillDate=#{till_utc}&interval=4&usageType=1&inclBtw=true"
    $stderr.puts "Fetching from EnergyZero API: #{api_url}"

    response = URI.open(api_url, "User-Agent" => user_agent).read
    data = JSON.parse(response)

    prices = data["Prices"]
    raise "No prices returned from EnergyZero API" if prices.nil? || prices.empty?

    all_price_values = prices.map { _1["price"] }

    hours = prices.map do |item|
      price_eur = item["price"]
      market_with_btw = convert_energyzero_price(price_eur)
      {
        "dateTime" => item["readingDate"],
        "priceTotalTaxIncluded" => market_with_btw + HANDLING_FEE_RAW + ENERGY_TAX_RAW,
        "pricingProfile" => classify_pricing_profile(price_eur, all_price_values)
      }
    end

    hours_reversed = hours.reverse

    $stderr.puts "Fetched #{hours_reversed.length} price entries from EnergyZero API."
    hours_reversed
  end

  def generate_data_file(entries, dat_file)
    colors = {
      "stale" => "0xCCCCCC",
      "low" => "0x999999",
      "normal" => "0x666666",
      "high" => "0x000000"
    }

    File.open(dat_file, "w") do |f|
      now = Time.now.localtime
      ascending = entries.reverse
      upcoming = ascending.reject { (Time.parse(_1["dateTime"]).localtime - now) < -3600 }
      # Identity, not rounded display cents: duplicate extremes must not each get a label.
      cheapest = upcoming.min_by { _1["priceTotalTaxIncluded"] }
      priciest = upcoming.max_by { _1["priceTotalTaxIncluded"] }

      graph_entries = ascending.reject { (Time.parse(_1["dateTime"]).localtime - now) < -3600 * 4 }
      graph_entries.each do |item|
        price_date = Time.parse(item["dateTime"]).localtime
        # Quarter rows only carry an x-axis label on the hour; hourly rows always do.
        # gnuplot's xtic(1) reads the two literal quotes as an empty label.
        label = price_date.min.zero? ? price_date.strftime("%H") : %q{""}
        total_price = display_price(item["priceTotalTaxIncluded"])
        color = (now - 3600 > price_date) ? colors["stale"] : colors[item["pricingProfile"]]
        boundary_price = if item.equal?(cheapest) || item.equal?(priciest)
          format("%.1f", item["priceTotalTaxIncluded"].to_f / PRICE_DIVISOR)
        end
        f.puts "#{label} #{total_price} #{color} #{boundary_price}"
      end

      puts "Data successfully written to #{dat_file}."
    end
  end
end
