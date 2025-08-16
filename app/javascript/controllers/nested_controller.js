// app/javascript/controllers/nested_controller.js
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
    static targets = ["template", "item"]

    add(event) {
        event.preventDefault()
        const html = this.templateTarget.innerHTML.replaceAll("NEW_ID", Date.now().toString())
        this.element.querySelector("#filters").insertAdjacentHTML("beforeend", html)
    }

    remove(event) {
        event.preventDefault()
        const item = event.target.closest("[data-nested-target='item']")
        if (item) item.remove()
    }
}
