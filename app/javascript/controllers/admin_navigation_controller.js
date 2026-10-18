import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["button", "menu"]

  connect() {
    this.mobile = window.matchMedia("(max-width: 999px)")
    this.open = false
    this.resize = () => { this.open = false; this.render() }
    this.mobile.addEventListener("change", this.resize)
    this.render()
  }

  disconnect() {
    this.mobile.removeEventListener("change", this.resize)
    this.menuTarget.hidden = false
    this.buttonTarget.hidden = true
  }

  toggle() {
    this.open = !this.open
    this.render()
  }

  close(event) {
    if (!this.mobile.matches || !this.open) return
    event.preventDefault()
    this.open = false
    this.render()
    this.buttonTarget.focus()
  }

  render() {
    const collapsed = this.mobile.matches && !this.open
    this.menuTarget.hidden = collapsed
    this.buttonTarget.hidden = !this.mobile.matches
    this.buttonTarget.setAttribute("aria-expanded", String(!collapsed))
  }
}
