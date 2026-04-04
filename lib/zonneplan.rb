require "open-uri"
require "nokogiri"
require "json"
require "time"

module Zonneplan
  PRICE_DIVISOR = 100_000
  ENERGYZERO_MULTIPLIER = 10_000_000

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
    doc = Nokogiri::HTML(html)

    next_data_json = doc.at_css("script#__NEXT_DATA__")
    unless next_data_json
      $stderr.puts "Script tag with id='__NEXT_DATA__' not found on page."
      return nil
    end

    data = JSON.parse(next_data_json.text)
    hours = data.dig("props", "pageProps", "data", "templateProps", "energyData", "electricity", "hours")
    unless hours
      $stderr.puts "Electricity hours data not found at expected path in __NEXT_DATA__."
      $stderr.puts "Available top-level keys: #{data.keys}"
      $stderr.puts "pageProps keys: #{data.dig("props", "pageProps")&.keys}" if data.dig("props", "pageProps")
      return nil
    end

    $stderr.puts "Fetched #{hours.length} price entries from Zonneplan."
    hours
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
      {
        "dateTime" => item["readingDate"],
        "priceTotalTaxIncluded" => convert_energyzero_price(price_eur),
        "pricingProfile" => classify_pricing_profile(price_eur, all_price_values)
      }
    end

    hours_reversed = hours.reverse

    $stderr.puts "Fetched #{hours_reversed.length} price entries from EnergyZero API."
    hours_reversed
  end

  def generate_data_file(hours, dat_file)
    colors = {
      "stale" => "0xCCCCCC",
      "low" => "0x999999",
      "normal" => "0x666666",
      "high" => "0x000000"
    }

    File.open(dat_file, "w") do |f|
      now = Time.now.localtime
      upcoming_hours = hours.reverse.reject { (Time.parse(_1["dateTime"]).localtime - now) < -3600 }
      prices = upcoming_hours.map { _1["priceTotalTaxIncluded"] }
      min_price = display_price(prices.min)
      max_price = display_price(prices.max)

      graph_hours = hours.reverse.reject { (Time.parse(_1["dateTime"]).localtime - now) < -3600 * 4 }
      graph_hours.each do |item|
        price_date = Time.parse(item["dateTime"]).localtime
        day_hour = price_date.strftime("%H")
        price = display_price(item["priceTotalTaxIncluded"])
        color = (now - 3600 > price_date) ? colors["stale"] : colors[item["pricingProfile"]]
        if (price_date - now) > -3600
          boundary_price = price if min_price == price.round(0) || max_price == price.round(0)
        end
        f.puts "#{day_hour} #{price} #{color} #{boundary_price}"
      end

      puts "Data successfully written to #{dat_file}."
    end
  end
end
