const KEY = 'halo-live-onboarded'
const SETUP_KEY = 'halo-live-client-setup'

export type ClientSetup = {
  propertyName: string
  unitDemo: string
  completedAt: string
}

export function hasCompletedOnboarding(): boolean {
  try {
    return localStorage.getItem(KEY) === '1'
  } catch {
    return false
  }
}

export function markOnboardingDone() {
  localStorage.setItem(KEY, '1')
}

export function resetOnboarding() {
  localStorage.removeItem(KEY)
  localStorage.removeItem(SETUP_KEY)
}

export function saveClientSetup(s: Omit<ClientSetup, 'completedAt'>) {
  const full: ClientSetup = { ...s, completedAt: new Date().toISOString() }
  localStorage.setItem(SETUP_KEY, JSON.stringify(full))
  markOnboardingDone()
  return full
}

export function loadClientSetup(): ClientSetup | null {
  try {
    const raw = localStorage.getItem(SETUP_KEY)
    return raw ? (JSON.parse(raw) as ClientSetup) : null
  } catch {
    return null
  }
}
