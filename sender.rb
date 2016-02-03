require 'rest-client'
require 'json'
require 'date'
require 'csv'
require 'yaml'

CONFIG = YAML.load_file('./secrets/secrets.yml')

date = Date.today-32

file_date = date.strftime("%Y%m")
reviews_directory = "reviews/"
csv_file_list = Array.new

# Handle muliple apps (and package name)
# Note that we will retrieve only the files from the current month (see date)
package_list = CONFIG["package_list"]
package_list.each do |package_name|
   csv_file_list <<  csv_file_name = "reviews_#{package_name}_#{file_date}.csv"
   #puts "gs://#{CONFIG["app_repo"]}/reviews/#{csv_file_name} #{reviews_directory}"
   system "BOTO_PATH=./secrets/.boto gsutil/gsutil cp -r gs://#{CONFIG["app_repo"]}/reviews/#{csv_file_name} #{reviews_directory}"
 end

# Commented to handle multiple packages (many apps)
##csv_file_name = "reviews_#{CONFIG["package_name"]}_#{file_date}.csv"
##system "BOTO_PATH=./secrets/.boto gsutil/gsutil cp -r gs://#{CONFIG["app_repo"]}/reviews/#{csv_file_name} reviews"


class Slack
  def self.notify(message)
    RestClient.post CONFIG["slack_url"], {
      payload:
      { text: message }.to_json
    },
    content_type: :json,
    accept: :json
  end
end

class Review
  def self.collection
    @collection ||= []
  end

  def self.send_reviews_from_date(date)
    #puts "In send_reviews_from_date method"
    message = collection.select do |r|
      r.submitted_at > date && (r.title || r.text)
    end.sort_by do |r|
      r.submitted_at
    end.map do |r|
      r.build_message
      #puts "Message built"
      #puts r.build_message
    end.join("\n")

    #puts message

    if message != ""
      Slack.notify(message)
    else
      print "No new reviews\n"
    end
  end

  #attr_accessor :text, :title, :submitted_at, :original_submitted_at, :rate, :device, :url, :version, :edited
  attr_accessor :text, :title, :app_bundle, :submitted_at, :original_submitted_at, :rate, :device, :url, :version, :edited


  def initialize data = {}
    @text = data[:text] ? data[:text].to_s.encode("utf-8") : nil
    @title = data[:title] ? "*#{data[:title].to_s.encode("utf-8")}*\n" : nil
    @app_bundle = data[:app_bundle] ? "*#{data[:app_bundle].to_s.encode("utf-8")}*\n" : nil
    #@app_bundle = data[:app_bundle] ? data[:app_bundle].to_s.encode("utf-8") : nil

    #puts data[:submitted_at].strftime("%Y%m")
    @submitted_at = data[:submitted_at] ? DateTime.parse(data[:submitted_at].encode("utf-8")) : nil
    @original_submitted_at = data[:original_submitted_at] ? DateTime.parse(data[:original_submitted_at].encode("utf-8")) : nil

    @rate = data[:rate].encode("utf-8").to_i
    @device = data[:device] ? data[:device].to_s.encode("utf-8") : nil
    @url = data[:url].to_s.encode("utf-8")
    @version = data[:version].to_s.encode("utf-8")
    @edited = data[:edited]
  end

  def notify_to_slack
    if text || title
      message = "*Rating: #{rate}* | version: #{version} | subdate: #{submitted_at}\n #{[title, text].join(" ")}\n <#{url}|Voir sur Google Play>"
      Slack.notify(message)
    end
  end

  def build_message
    date = if edited
             "subdate: #{original_submitted_at.strftime("%d.%m.%Y at %I:%M%p")}, edited at: #{submitted_at.strftime("%d.%m.%Y at %I:%M%p")}"
           else
             "subdate: #{submitted_at.strftime("%d.%m.%Y at %I:%M%p")}"
           end

    stars = rate.times.map{"★"}.join + (5 - rate).times.map{"☆"}.join

    [
      "\n#{app_bundle}",
      "#{stars}",
      "Version: #{version} | #{date}",
      "#{[title, text].join(" ")}",
      "<#{url}|Voir sur Google Play>\n"
    ].join("\n")
  end
end

csv_file_list.each do |csv_file_name|
  #puts "In file list"
  if File.exist?("./#{reviews_directory}#{csv_file_name}")
    puts "File exists"
    CSV.foreach("#{reviews_directory}#{csv_file_name}", encoding: 'bom|utf-16le', headers: true) do |row|
      # To push only reviews with not reply, encapsulate the collection
      # building with a if row[11].nil? loop
      # Here we are pushing all rewiews

      #if row[11].nil?
        Review.collection << Review.new({
          app_bundle: row[0],
          text: row[11],
          title: row[10],
          submitted_at: row[7],
          edited: (row[5] != row[7]),
          original_submitted_at: row[5],
          rate: row[9],
          device: row[4],
          url: row[15],
          version: row[1],
       })
        puts row
      #end
    end
  end
end

Review.send_reviews_from_date(date)
