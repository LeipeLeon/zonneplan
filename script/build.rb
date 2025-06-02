require 'open-uri'
require 'nokogiri'
require 'json'
require 'date'

url = 'https://www.zonneplan.nl/energie/dynamische-energieprijzen'
dat_file = 'build/hours.dat'
html = URI.open(url).read
doc = Nokogiri::HTML(html)

if (next_data_json = doc.at_css('script#__NEXT_DATA__'))
  data = JSON.parse(next_data_json.text)

  if (hours = data.dig('props', 'pageProps', 'data', 'templateProps', 'energyData', 'electricity', 'hours'))
    File.open(dat_file, 'w') do |f|
      f.puts "Zonneplan #{DateTime.parse(hours[0]['dateTime']).strftime('%d-%m-%Y')}"

      hours.reverse!
      colors = {
        "normal" => "0xCCCCCC",
        "high" => "0x666666",
        "low" => "0x000000"
      }

      hours.each do |item|
        d_t = DateTime.parse(item['dateTime'])
        day_hour = d_t.hour
        price = item['priceTotalTaxIncluded'].to_f / 100000
        color = colors[item['pricingProfile']]
        f.puts "#{day_hour} #{price} #{color}"
      end

      puts "Data successfully written to #{dat_file}."
    end
  else
    throw "No electricity hours data found in __NEXT_DATA__."
  end
else
  throw "Script tag with id='__NEXT_DATA__' not found."
end
