import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["card", "detail"]

  connect() {
    const selected = this.cardTargets.findIndex(card => card.getAttribute("aria-pressed") === "true")
    this.show(selected < 0 ? 0 : selected)
  }

  select(event) {
    this.show(event.params.index)
  }

  navigate(event) {
    const current = this.cardTargets.indexOf(event.target)
    if (current < 0 || event.altKey || event.ctrlKey || event.metaKey) return

    let index
    switch (event.key) {
      case "ArrowRight": index = (current + 1) % this.cardTargets.length; break
      case "ArrowLeft": index = (current - 1 + this.cardTargets.length) % this.cardTargets.length; break
      case "Home": index = 0; break
      case "End": index = this.cardTargets.length - 1; break
      default: return
    }
    event.preventDefault()
    this.show(index, true)
  }

  show(index, focus = false) {
    if (!Number.isInteger(index) || !this.detailTargets[index]) return

    this.cardTargets.forEach((card, position) => {
      card.setAttribute("aria-pressed", String(position === index))
      card.tabIndex = position === index ? 0 : -1
    })
    this.detailTargets.forEach((detail, position) => { detail.hidden = position !== index })
    if (focus) {
      this.cardTargets[index].focus({ preventScroll: true })
      this.cardTargets[index].scrollIntoView({ block: "nearest", inline: "nearest", behavior: "auto" })
    }
  }
}
