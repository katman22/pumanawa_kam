import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["tablist", "tab", "panel"]

  connect() {
    this.tablistTarget.hidden = false
    const selected = this.tabTargets.findIndex(tab => tab.getAttribute("aria-selected") === "true")
    this.show(selected < 0 ? 0 : selected)
  }

  select(event) {
    this.show(this.tabTargets.indexOf(event.currentTarget))
  }

  navigate(event) {
    const index = this.tabTargets.indexOf(event.currentTarget)
    const last = this.tabTargets.length - 1
    let next
    switch (event.key) {
      case "ArrowRight": next = (index + 1) % (last + 1); break
      case "ArrowLeft": next = (index + last) % (last + 1); break
      case "Home": next = 0; break
      case "End": next = last; break
      default: return
    }
    event.preventDefault()
    this.show(next)
    this.tabTargets[next].focus()
  }

  show(index) {
    if (!this.panelTargets[index]) return
    this.tabTargets.forEach((tab, position) => {
      tab.setAttribute("aria-selected", String(position === index))
      tab.tabIndex = position === index ? 0 : -1
    })
    this.panelTargets.forEach((panel, position) => {
      panel.setAttribute("role", "tabpanel")
      panel.tabIndex = 0
      panel.hidden = position !== index
    })
  }
}
