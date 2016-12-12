class GetFlightsService

  def initialize(search_params)
    @search_params = search_params
  end

  def call
    flight_result(request_flight_result)
  end

  private

  def request_flight_result
    api_results = []
    global_trips_results = []
    departure_date = @search_params[:departuredate].to_date
    returndate = @search_params[:returndate].to_date
    end_period_date =  @search_params[:end_period]

    while returndate <= end_period_date
      departuredate_to_string = (departure_date).to_s
      returndate_to_string = (returndate).to_s
      api_results = SacsRuby::API::InstaFlightsSearch.get(
        origin: @search_params[:origin],
        destination:  @search_params[:destination],
        departuredate:  departuredate_to_string,
        returndate:  returndate_to_string,
        limit: '5',
        onlineitinerariesonly: "N",
        sortby: "totalfare",
        order: "asc",
        eticketsonly: "N"
        # sortby2: "totalfare",
        # order2: "asc"
      )

      api_results["PricedItineraries"].each do |trip|
        global_trips_results << trip
      end

      departure_date += 1
      returndate += 1
    end

    global_trips_results
  end



  def processing(segment_result, stop_number)
    {
       start_segment_departure_airport: segment_result["DepartureAirport"]["LocationCode"],
       start_segment_departure_datetime: segment_result["DepartureDateTime"],
       start_segment_departure_timezone: segment_result["DepartureTimeZone"],
       start_segment_arrival_airport: segment_result["ArrivalAirport"]["LocationCode"],
       start_segment_arrival_datetime: segment_result["ArrivalDateTime"],
       start_segment_arrival_timezone: segment_result["ArrivalTimeZone"],
       start_segment_flight_number: segment_result["OperatingAirline"]["FlightNumber"],
       start_segment_marketing_airline: segment_result["OperatingAirline"]["Code"],
       stops: stop_number - 1
    }
  end

  def stops_duration_calcul(segment, segment_number)
    i = 0
    duration_stop = 0
    while i < segment_number - 1
      duration_stop += (segment[i + 1]["DepartureDateTime"].to_time - segment[i]["ArrivalDateTime"].to_time).to_i / 60
      i += 1
    end
    duration_stop
  end

  def select_time_duration(results)
    results.select! { |record| record[:flight_values][2].last[:start_trip_duration] < 1440 && record[:flight_values][2].last[:return_trip_duration] }
  end

  def sort_by_price(results)
    results.sort_by { |record| record[:flight_values][2].last[:price] }
  end

  def top5(results)
    results[0..9]
  end

   def trip_generator(result)
    trip = {}
    trip[:depart_flights] = []
    trip[:return_flights] = []
    trip[:details] = {}
      result[:flight_values][0].each_with_index do |flight, index|
          flights_object_depart = Flight.new(departure_airport: flight[:start_segment_departure_airport],
          departure_datetime: flight[:start_segment_departure_datetime],
          departure_timezone: flight[:start_segment_departure_timezone],
          arrival_airport: flight[:start_segment_arrival_airport],
          arrival_datetime: flight[:start_segment_arrival_datetime],
          arrival_timezone: flight[:start_segment_arrival_timezone],
          flight_number: flight[:start_segment_flight_number],
          marketing_airline: "http://0.omg.io/wego/image/upload/c_fit,w_200,h_70/flights/airlines_rectangular/" + flight[:start_segment_marketing_airline] + ".png",
          step: index
          )


        trip[:depart_flights] << flights_object_depart
      end
      result[:flight_values][1].each_with_index do |flight, index|
         flights_object_return = Flight.new(departure_airport: flight[:start_segment_departure_airport],
          departure_datetime: flight[:start_segment_departure_datetime],
          departure_timezone: flight[:start_segment_departure_timezone],
          arrival_airport: flight[:start_segment_arrival_airport],
          arrival_datetime: flight[:start_segment_arrival_datetime],
          arrival_timezone: flight[:start_segment_arrival_timezone],
          flight_number: flight[:start_segment_flight_number],
          marketing_airline: "http://0.omg.io/wego/image/upload/c_fit,w_200,h_70/flights/airlines_rectangular/" + flight[:start_segment_marketing_airline] + ".png",
          step: index
          )

        trip[:return_flights] << flights_object_return
      end
      trip[:details] = result[:flight_values][2][0]
      trip
    end




  def flight_result(results_request)
    raw_results = []
    # Iteration to select only desired information sorted by flights
    results_request.each do | result |
      # depart_info = result["PricedItineraries"][0]["AirItinerary"]["OriginDestinationOptions"]["OriginDestinationOption"][0]
      depart_segments_info = result["AirItinerary"]["OriginDestinationOptions"]["OriginDestinationOption"][0]["FlightSegment"]
      depart_segment_number = depart_segments_info.size
      return_segments_info = result["AirItinerary"]["OriginDestinationOptions"]["OriginDestinationOption"][1]["FlightSegment"]
      # return_info = result["PricedItineraries"][0]["AirItinerary"]["OriginDestinationOptions"]["OriginDestinationOption"][1]
      return_segment_number = return_segments_info.size
      itin_fares = result["AirItineraryPricingInfo"]["ItinTotalFare"]

      i = results_request.index(result) + 1
      flights_info = {}
      flights_info[:flight_id] = i
      flights_info[:flight_values] = []
      flights_info[:flight_values][0] = []
      flights_info[:flight_values][1] = []
      flights_info[:flight_values][2] = []
      depart_segment_results = []
      return_segment_results = []
      price_results = []
      depart_flight_duration = 0
      return_flight_duration = 0

      depart_segments_info.each do | segment_result |
        flights_info[:flight_values][0] <<  processing(segment_result, depart_segment_number)
        depart_flight_duration += segment_result["ElapsedTime"]
      end

      return_segments_info.each do | segment_result |
        flights_info[:flight_values][1] << processing(segment_result, return_segment_number)
        return_flight_duration += segment_result["ElapsedTime"]
      end

      depart_stops_duration = stops_duration_calcul(depart_segments_info, depart_segment_number)
      return_stops_duration = stops_duration_calcul(return_segments_info, return_segment_number)

      flights_info[:flight_values][2] << { price: itin_fares["TotalFare"]["Amount"],
        currency: result["AirItineraryPricingInfo"]["ItinTotalFare"]["TotalFare"]["CurrencyCode"],
        start_trip_duration: depart_flight_duration + depart_stops_duration,
        return_trip_duration: return_flight_duration + return_stops_duration
        # start_trip_duration: Time.at((depart_flight_duration + depart_stops_duration)*60).utc.strftime("%Hh%M"),
        # return_trip_duration: Time.at((return_flight_duration + return_stops_duration)*60).utc.strftime("%Hh%M")
      }
      raw_results << flights_info

    end

    selected_results = select_time_duration(raw_results)
    sorted_results = sort_by_price(selected_results)
    top5_results = top5(sorted_results)

    trips = []
    top5_results.each do |result|
      trips << trip_generator(result)
    end
    trips
  end
end



