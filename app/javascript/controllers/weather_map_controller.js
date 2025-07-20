import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["dropdownButton", "playPause", "timeSlider", "timeLabel", "pointerData"]

  connect() {
    console.log("🌦️ weather-map Stimulus controller connected")

    maptilersdk.config.apiKey = this.data.get("apiKey")
    this.weatherLayers = {
      precipitation: { layer: null, value: "value", units: " mm" },
      pressure: { layer: null, value: "value", units: " hPa" },
      radar: { layer: null, value: "value", units: " dBZ" },
      temperature: { layer: null, value: "value", units: "°" },
      wind: { layer: null, value: "speedMetersPerSecond", units: " mph" }
    }

    this.activeLayer = null
    this.isPlaying = false
    this.pointerLngLat = null

    this.map = new maptilersdk.Map({
      container: this.element.querySelector("#map"),
      style: maptilersdk.MapStyle.STREETS,
      zoom: 7,
      center: [parseFloat(this.data.get("lng")), parseFloat(this.data.get("lat"))],
      hash: true,
      projectionControl: true
    })

    this.map.on('load', () => {
      this.map.setPaintProperty("Water", 'fill-color', "rgba(0, 0, 0, 0.4)")
      this.changeWeatherLayer(this.data.get("type"))
    })

    this.map.on('mousemove', this.handleMouseMove.bind(this))

    this.playPauseTarget.addEventListener("click", () => this.togglePlayPause())
    this.timeSliderTarget.addEventListener("input", e => this.updateAnimationTime(e))
  }

  handleMouseMove(e) {
    this.pointerLngLat = e.lngLat
    const layer = this.weatherLayers[this.activeLayer]?.layer
    const valKey = this.weatherLayers[this.activeLayer]?.value
    const units = this.weatherLayers[this.activeLayer]?.units
    const value = layer?.pickAt(this.pointerLngLat.lng, this.pointerLngLat.lat)

    if (value) {
      if (this.activeLayer === 'temperature') {
        value[valKey] = (value[valKey] * 9) / 5 + 32;
      } else if (this.activeLayer === 'wind') {
        value[valKey] = value[valKey] * 2.23694; // m/s → mph
      }
    }

    this.pointerDataTarget.innerText = value ? `${value[valKey].toFixed(1)}${units}` : '—'
  }

  togglePlayPause() {
    const layer = this.weatherLayers[this.activeLayer]?.layer
    if (!layer) return

    if (this.isPlaying) {
      layer.animateByFactor(0)
      this.playPauseTarget.innerText = " Play "
    } else {
      layer.animateByFactor(800)
      this.playPauseTarget.innerText = " Pause "
    }

    this.isPlaying = !this.isPlaying
  }

  updateAnimationTime(evt) {
    const layer = this.weatherLayers[this.activeLayer]?.layer
    if (!layer) return
    let val = parseInt(evt.target.value)
    val = Math.max(val, parseInt(this.timeSliderTarget.min))
    val = Math.min(val, parseInt(this.timeSliderTarget.max))
    layer.setAnimationTime(val / 1000)
  }

  changeWeatherLayer(type) {
    if (type === this.activeLayer) return;

    const oldLayer = this.weatherLayers[this.activeLayer]?.layer;
    if (oldLayer) {
      this.map.setLayoutProperty(this.activeLayer, 'visibility', 'none');
    }

    this.activeLayer = type;
    let newLayer = this.weatherLayers[type]?.layer;

    if (!newLayer) {
      newLayer = this.createWeatherLayer(type);
      if (newLayer) {
        this.map.addLayer(newLayer, 'Water');
      }
    } else {
      this.map.setLayoutProperty(type, 'visibility', 'visible');
    }

    this.isPlaying = false; // <-- Reset playback state
    this.playPauseTarget.innerText = " Play ";

    this.setAnimation(newLayer);
  }


  createWeatherLayer(type) {
    let layer
    switch (type) {
      case 'precipitation':
        layer = new maptilerweather.PrecipitationLayer({ id: 'precipitation' })
        break
      case 'pressure':
        layer = new maptilerweather.PressureLayer({ id: 'pressure', opacity: 0.8 })
        break
      case 'radar':
        layer = new maptilerweather.RadarLayer({ id: 'radar', opacity: 0.8 })
        break
      case 'temperature':
        layer = new maptilerweather.TemperatureLayer({
          id: 'temperature',
          colorramp: maptilerweather.ColorRamp.builtin.TEMPERATURE_3
        })
        break
      case 'wind':
        layer = new maptilerweather.WindLayer({
          id: 'wind',
          windStyle: 'arrows',
          arrowColor: '#ffffff',
          arrowSize: 1.2,
          particleDensity: 0.5,
          particleSpeed: 0
        })
        break
    }

    if (!layer) return null

    layer.on("tick", () => {
      const now = new Date()
      const hourMs = 3600000
      const clampedMin = new Date(now.getTime() - hourMs)
      const clampedMax = new Date(now.getTime() + hourMs)
      const current = layer.getAnimationTimeDate()

      if (current > clampedMax) {
        layer.setAnimationTime(clampedMin.getTime() / 1000)
      }

      this.updateTime(layer)
      this.updatePointerValue()
    })

    layer.on("animationTimeSet", () => {
      this.updateTime(layer)
    })

    layer.on("sourceReady", () => {
      const now = new Date()
      const hourMs = 3600000

      const startDate = layer.getAnimationStartDate()
      const endDate = layer.getAnimationEndDate()
      const currentDate = layer.getAnimationTimeDate()

      const clampedMin = new Date(Math.max(+startDate, +now - hourMs))
      const clampedMax = new Date(Math.min(+endDate, +now + hourMs))

      this.timeSliderTarget.min = +clampedMin
      this.timeSliderTarget.max = +clampedMax

      let initialValue = +currentDate
      if (initialValue < +clampedMin) initialValue = +clampedMin
      if (initialValue > +clampedMax) initialValue = +clampedMax

      this.timeSliderTarget.value = initialValue

      this.updateTime(layer)
    })

    this.weatherLayers[type].layer = layer
    return layer
  }

  setAnimation(layer) {
    if (!layer) return
    layer.setAnimationTime(parseInt(this.timeSliderTarget.value / 1000))
    layer.animateByFactor(this.isPlaying ? 1800 : 0)
  }

  updateTime(layer) {
    const d = layer.getAnimationTimeDate()
    this.timeSliderTarget.value = +d
    if (d instanceof Date) {
      this.timeLabelTarget.innerText = d.toLocaleString(undefined, {
        month: 'short',
        day: 'numeric',
        hour: '2-digit',
        minute: '2-digit'
      })
    }
  }

  updatePointerValue() {
    if (!this.pointerLngLat) return
    const layer = this.weatherLayers[this.activeLayer]?.layer
    const valKey = this.weatherLayers[this.activeLayer]?.value
    const units = this.weatherLayers[this.activeLayer]?.units
    const value = layer?.pickAt(this.pointerLngLat.lng, this.pointerLngLat.lat)
    if (value) {
      if (this.activeLayer === 'temperature') {
        value[valKey] = (value[valKey] * 9) / 5 + 32;
      } else if (this.activeLayer === 'wind') {
        value[valKey] = value[valKey] * 2.23694; // m/s → mph
      }
    }
    this.pointerDataTarget.innerText = value ? `${value[valKey].toFixed(1)}${units}` : '—'
  }

  selectLayer(event) {
    event.preventDefault()
    const button = this.dropdownButtonTarget
    const layerType = event.currentTarget.dataset.layerType
    const label = event.currentTarget.textContent.trim()

    button.textContent = label
    this.changeWeatherLayer(layerType)
  }

}
