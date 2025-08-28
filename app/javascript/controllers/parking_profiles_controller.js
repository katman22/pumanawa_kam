import { Controller } from "@hotwired/stimulus"


export default class extends Controller {
    // static targets = ["button", "input", "effectiveFrom", "effectiveTo"]
    //
    // select(event) {
    //     event.preventDefault()
    //     const link = event.target.closest("[data-value]")
    //     if (!link) return
    //
    //     const value = link.dataset.value
    //     const label = link.textContent.trim()
    //
    //     this.buttonTarget.textContent = label
    //     this.inputTarget.value = value
    // }

    connect() {
        // // Initialize button label from saved value
        // if (this.inputTarget.value) {
        //     const item = this.element.querySelector(`[data-value="${this.inputTarget.value}"]`)
        //     if (item) this.buttonTarget.textContent = item.textContent.trim()
        // }
    }
}

