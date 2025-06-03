# Generate an image for the [TRMNL](https://usetrmnl.com/) display.

This image can be used with the [Image display](https://usetrmnl.com/plugin_settings?keyname=image_display) or [Alias](https://usetrmnl.com/plugin_settings?keyname=alias) plugin

![](https://leipeleon.github.io/zonneplan/diffused.png)

- dithered png: <https://leipeleon.github.io/zonneplan/dithered.png>
- diffused png: <https://leipeleon.github.io/zonneplan/diffused.png>
- diffused bmp: <https://leipeleon.github.io/zonneplan/diffused.bmp>
- color: <https://leipeleon.github.io/zonneplan/hours.png>

1. Make a screenshot of https://www.zonneplan.nl/energie/dynamische-energieprijzen
2. crop out the graphic w/ imagemagick
3. create a [diffused image](https://leipeleon.github.io/zonneplan/diffused.png)
4. Upload it to github-pages
5. PROFIT!

## Further reading for investigation

- https://help.usetrmnl.com/en/articles/11479051-image-display
- https://docs.usetrmnl.com/go/imagemagick-guide
- https://usage.imagemagick.org/crop/#crop


## Scrape site

Content is in `<script id="__NEXT_DATA__" type="application/json">`
-> "props.pageProps.data.templateProps.energyData.electricity.hours[]"

divide element values by 100000

```json
{
  "props": {
    "pageProps": {
      "data": {
        "templateProps" : {
          "energyData": {
            "__typename": "EnergyData",
            "electricity": {
              "__typename": "Electricity",
              "hours": [
                {
                  "__typename": "ElectricityHour",
                  "dateTime": "2025-05-31T21:00:00.000000Z",
                  "priceTotalTaxIncluded": 2636093,
                  "marketPrice": 997900,
                  "priceInclHandlingVat": 1407459,
                  "priceEnergyTaxes": 1228634,
                  "priceCbsAverage": 0.4,
                  "pricingProfile": "normal"
                },
                {
                  // ....
                }
              ]
            }
          },
        }
      }
    }
  }
}
```
