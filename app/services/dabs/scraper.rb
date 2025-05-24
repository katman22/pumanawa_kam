require 'selenium-webdriver'
require 'webdrivers'

module Dabs
  class Scraper
    def initialize(product_name)
      @product_name = product_name
    end

    def fetch_results
      options = Selenium::WebDriver::Chrome::Options.new
      options.add_argument('--headless')
      options.add_argument('--disable-gpu')
      options.add_argument('--no-sandbox')

      driver = Selenium::WebDriver.for :chrome, options: options
      wait = Selenium::WebDriver::Wait.new(timeout: 20)

      begin
        puts "[DABS] Navigating to DABS site..."
        driver.navigate.to 'https://webapps2.abc.utah.gov/ProdApps/ProductLocatorCore'

        # Step 1: Set the input field's value via JS and trigger change/input events
        js_script = <<~JS
          const input = document.getElementById('itemname');
          input.value = "#{@product_name}";
          input.dispatchEvent(new Event('input', { bubbles: true }));
          input.dispatchEvent(new Event('change', { bubbles: true }));
        JS

        driver.execute_script(js_script)
        puts "[DABS] Set input value via JS: #{@product_name}"

        # Step 2: Trigger the reloadtable() function
        driver.execute_script("reloadtable();")
        puts "[DABS] Triggered reloadtable()"

        # Step 3: Wait for new rows
        wait.until do
          driver.find_elements(css: '#productTable tbody tr').size > 0 rescue false
        end

        # Step 4: Extract rows
        rows_data = driver.execute_script(<<~JS)
          return Array.from(document.querySelectorAll('#productTable tbody tr')).map(row => {
            const cells = Array.from(row.querySelectorAll('td')).map(td => td.innerText.trim());
            return {
              name: cells[0],
              sku: cells[1],
              subcategory: cells[2],
              status: cells[3],
              warehouse_qty: cells[4],
              store_qty: cells[5],
              on_order_qty: cells[6],
              price: cells[7]
            };
          });
        JS

        puts "[DABS] Fetched #{rows_data.size} result(s):"
        rows_data.each { |r| puts "→ #{r['name']} | #{r['subcategory']} | Store: #{r['store_qty']}" }

        rows_data
      ensure
        driver.quit
      end
    end
  end
end
