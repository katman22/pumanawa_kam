import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["input"]

  connect() {
    console.log("🚀 recent-location Stimulus controller connected");
  }

  select(event) {
    const row = event.currentTarget
    const lat = row.dataset.lat
    const lng = row.dataset.lng

    this.inputTarget.value = `${lat}, ${lng}`
  }
}