import { Controller } from "@hotwired/stimulus"

// Fragments are not sent to Rails. Canonicalize old evidence links without
// loading hidden histories, preserving the native link fallback without JS.
export default class extends Controller {
  static values = { tab: String, sections: Object }

  connect() {
    this.follow = () => {
      const section = window.location.hash.slice(1).replace(/-heading$/, "")
      if (!Object.prototype.hasOwnProperty.call(this.sectionsValue, section)) return
      const tab = this.sectionsValue[section]
      if (!tab || tab === this.tabValue) return
      const url = new URL(window.location.href)
      url.searchParams.set("tab", tab)
      window.location.replace(url.href)
    }
    window.addEventListener("hashchange", this.follow)
    this.follow()
  }

  disconnect() {
    window.removeEventListener("hashchange", this.follow)
  }
}
