require 'active_support/all'
require 'rest_client'
require 'json'
require 'flight_stats/url_builder'

module FlightStats
  class Schedule
    attr_accessor :airports, :airport_offsets

    def initialize
      @airport_offsets = {}
    end

    def flights_arriving_before(time, from, to, now = DateTime.now)
      check_for_past_time(time, now)
      builder = FlightStats::UrlBuilder.new.from(from).to(to).date(time)
      flights = arriving_flights(builder, time)
      if flights.nil? || flights.length == 0
        earlier_time = time.to_datetime - 1
        check_for_past_time(earlier_time, now)
        builder.from(from).to(to).date(earlier_time)
        flights = arriving_flights(builder, time)
      end
      flights
    end

    def flights_departing_after(time, from, to, now = DateTime.now)
      check_for_past_time(time, now)
      builder = FlightStats::UrlBuilder.new.from(from).to(to).date(time)
      flights = departing_flights(builder, time)
      if flights.nil? || flights.length == 0
        builder.from(from).to(to).date(time.to_datetime + 1)
        flights = departing_flights(builder, time)
      end
      flights
    end

    private

    def check_for_past_time(time, now = DateTime.now)
      raise(ArgumentError, time_error_message(now, time)) unless time > now
    end

    def time_error_message(now, time)
      "Time requested in the past (request: #{time}, now: #{now}"
    end

    def scheduled_flights(url)
      json = RestClient::Request.execute(method:     :get,
                                  url:        url,
                                  headers:    headers,
                                  verify_ssl: false)
      @airports = JSON.parse(json)["appendix"]["airports"]
      flights = JSON.parse(json)["scheduledFlights"]

      add_utc_time(flights)
    end

    def add_utc_time(flights)
      flights.each do |flight|
        flight["arrivalTimeUtc"] = arrival_time_utc(flight)
        flight["departureTimeUtc"] = departure_time_utc(flight)
      end
      flights
    end

    def arrival_time_utc(flight)
      utc = flight["arrivalTime"].to_datetime
      utc.change(offset: tz_offset(flight["arrivalAirportFsCode"])).to_s
    end

    def departure_time_utc(flight)
      utc = flight["departureTime"].to_datetime
      utc.change(offset: tz_offset(flight["departureAirportFsCode"])).to_s
    end

    def tz_offset(airport)
      return @airport_offsets[airport] unless @airport_offsets[airport].nil?
      offset_from_airports(airport)
    end

    def offset_from_airports(airport)
      offset = @airports.select { |a| a["fs"] == airport }[0]["utcOffsetHours"]
      @airport_offsets[airport] = sprintf("%+05.f", (offset.to_f * 100.0))
      @airport_offsets[airport]
    end

    def arriving_flights(builder, time)
      scheduled_flights(builder.schedule_arriving_url).tap do |flights|
        flights.select! { |f| f["arrivalTimeUtc"].to_datetime < time }
      end
    end

    def departing_flights(builder, time)
      scheduled_flights(builder.schedule_departing_url).tap do |flights|
        flights.select! { |f| f["departureTimeUtc"].to_datetime > time }
      end
    end

    def headers
      {
        "appId"  => "89cd457c",
        "appKey" => "be2705cf426fe89bd49cbf1534d10978",
      }
    end
  end
end
