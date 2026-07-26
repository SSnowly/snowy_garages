const resourceName = window.GetParentResourceName ? window.GetParentResourceName() : 'snowy_garages'

async function nuiPost(endpoint, payload) {
    const resp = await fetch(`https://${resourceName}/${endpoint}`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json; charset=UTF-8' },
        body: JSON.stringify(payload || {}),
    })
    try { return await resp.json() } catch { return null }
}

const panel  = document.getElementById('panel')
const titleEl = document.getElementById('title')
const bodyEl  = document.getElementById('body')
const closeEl = document.getElementById('close')

let state = null
let expandedPlate = null

function buildSection(labelText, entries) {
    if (!entries || entries.length === 0) return null

    const label = document.createElement('div')
    label.className = 'section-label'
    label.textContent = labelText

    const fragment = document.createDocumentFragment()
    fragment.appendChild(label)

    for (const entry of entries) {
        fragment.appendChild(buildVehicleRow(entry))
    }

    return fragment
}

function buildVehicleRow(entry) {
    const wrapper = document.createElement('div')
    wrapper.className = 'vehicle'
    wrapper.dataset.plate = entry.plate

    const row = document.createElement('div')
    row.className = 'vehicle-row'

    const plate = document.createElement('div')
    plate.className = 'plate'
    plate.textContent = entry.plate
    row.appendChild(plate)

    const status = document.createElement('div')
    status.className = 'status' + (entry.impounded ? '' : ' lost')
    status.textContent = entry.status
    row.appendChild(status)

    row.addEventListener('click', () => toggleVehicle(entry.plate))
    wrapper.appendChild(row)

    const actions = document.createElement('div')
    actions.className = 'vehicle-actions'

    if (entry.locked && entry.lockLabel) {
        const lockInfo = document.createElement('div')
        lockInfo.className = 'lock-info'
        lockInfo.textContent = entry.lockLabel
        actions.appendChild(lockInfo)
    }

    if (entry.reason) {
        const reasonEl = document.createElement('div')
        reasonEl.className = 'reason-info'
        reasonEl.textContent = entry.reason
        actions.appendChild(reasonEl)
    }

    const fee = document.createElement('div')
    fee.className = 'fee'
    fee.textContent = entry.feeLabel || ''
    actions.appendChild(fee)

    const cashBtn = document.createElement('div')
    cashBtn.className = 'release-btn' + (entry.locked ? ' locked' : '')
    cashBtn.textContent = `${state.releaseLabel} (${state.cashLabel})`
    if (!entry.locked) cashBtn.addEventListener('click', (e) => { e.stopPropagation(); release(entry.plate, 'cash') })
    actions.appendChild(cashBtn)

    const bankBtn = document.createElement('div')
    bankBtn.className = 'release-btn' + (entry.locked ? ' locked' : '')
    bankBtn.textContent = `${state.releaseLabel} (${state.bankLabel})`
    if (!entry.locked) bankBtn.addEventListener('click', (e) => { e.stopPropagation(); release(entry.plate, 'bank') })
    actions.appendChild(bankBtn)

    wrapper.appendChild(actions)
    return wrapper
}

function render() {
    titleEl.textContent = state.title
    bodyEl.innerHTML = ''

    const personal = buildSection(state.personalLabel, state.personal)
    if (personal) bodyEl.appendChild(personal)

    const company = buildSection(state.companyLabel, state.company)
    if (company) bodyEl.appendChild(company)
}

function toggleVehicle(plate) {
    if (expandedPlate === plate) {
        collapseAll()
        return
    }

    collapseAll()
    expandedPlate = plate
    const wrapper = bodyEl.querySelector(`.vehicle[data-plate="${cssEscape(plate)}"]`)
    if (wrapper) wrapper.classList.add('expanded')

    nuiPost('impoundPreview', { plate })
}

function collapseAll() {
    expandedPlate = null
    for (const el of bodyEl.querySelectorAll('.vehicle.expanded')) {
        el.classList.remove('expanded')
    }
}

async function release(plate, accountType) {
    const ok = await nuiPost('impoundRelease', { plate, accountType })
    if (!ok) return
    close()
}

function cssEscape(value) {
    return window.CSS && CSS.escape ? CSS.escape(value) : value.replace(/"/g, '\\"')
}

function close() {
    panel.classList.add('hidden')
    nuiPost('impoundClose', {})
}

closeEl.addEventListener('click', close)

document.addEventListener('keyup', (e) => {
    if (e.key === 'Escape' && !panel.classList.contains('hidden')) close()
})

window.addEventListener('message', ({ data }) => {
    if (data.action === 'openImpound') {
        state = data
        expandedPlate = null
        render()
        panel.classList.remove('hidden')
    }
})
