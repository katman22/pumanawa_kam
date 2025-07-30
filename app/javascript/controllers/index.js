// Import and register all your controllers from the importmap via controllers/**/*_controller
import { application } from "controllers/application"

import RecentLocationController from "controllers/recent_location_controller"
application.register("recent-location", RecentLocationController)

import WeatherMapController from "controllers/weather_map_controller"
application.register("weather-map", WeatherMapController)

import WeatherMapMobileController from "controllers/weather_map_mobile_controller"
application.register("weather-map-mobile", WeatherMapMobileController)