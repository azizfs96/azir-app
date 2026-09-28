/** Types mirroring the Laravel API resources (ARCHITECTURE.md §7). */

export type BookingStatus =
  | 'pending' | 'confirmed' | 'checked_in' | 'completed' | 'cancelled' | 'no_show'

export interface AuthUser {
  id: number
  name: string
  phone: string | null
  email: string | null
  role: 'customer' | 'merchant_owner' | 'merchant_staff' | 'admin'
  locale: 'ar' | 'en'
  merchant?: {
    display_name: string
    status: 'pending' | 'approved' | 'suspended' | 'rejected'
    onboarding_step: number
    onboarding_complete: boolean
  }
}

export interface DashboardData {
  date: string
  timezone: string
  today: {
    total: number; pending: number; confirmed: number
    checked_in: number; completed: number; cancelled: number; no_show: number
  }
  revenue: { amount: number; currency: string; basis: string }
  store: { token: string; name: string; is_published: boolean; deep_link: string }
  upcoming: Array<{
    id: number; reference: string; time: string; starts_at: string
    status: BookingStatus; service: string | null
    staff: string | null; customer: string | null
  }>
}

export interface MerchantBooking {
  id: number
  reference: string
  status: BookingStatus
  starts_at: string
  ends_at: string
  time: string
  duration_minutes: number
  price: number
  payment_status: string
  service: string | null
  staff: string | null
  branch: string | null
  customer: { name: string | null; phone: string | null }
  notes: string | null
  allowed_transitions: BookingStatus[]
}

export interface Service {
  id: number
  name: string
  name_ar: string
  name_en: string | null
  description: string | null
  price: number
  currency: string
  duration_minutes: number
  category_id: number | null
}

export interface StaffMember {
  id: number
  name: string
  title_ar: string | null
  title_en: string | null
  branch_id: number | null
  gender: 'male' | 'female' | null
  is_active: boolean
  is_bookable: boolean
  service_ids: number[]
  performs_all_services: boolean
  schedule: ScheduleRow[]
}

export interface TimeOffEntry {
  id: number
  staff_id: number | null
  branch_id: number | null
  starts_at: string
  ends_at: string
  reason: string | null
}

export interface AffectedBooking {
  id: number
  reference: string
  starts_at: string
  service: string | null
  customer: string | null
}

export interface ScheduleRow {
  day_of_week: number
  starts_at?: string
  ends_at?: string
  opens_at?: string
  closes_at?: string
  break_starts_at?: string | null
  break_ends_at?: string | null
  is_off?: boolean
  is_closed?: boolean
}

export interface Branch {
  id: number
  name: string
  address: string | null
  city: string | null
  phone: string | null
  google_maps_url: string | null
  latitude: number | null
  longitude: number | null
  is_active: boolean
  slot_interval_minutes: number
  buffer_before_minutes: number
  buffer_after_minutes: number
  schedule: ScheduleRow[]
}

export interface BookingSettings {
  staff_selection: boolean
  branch_selection: boolean
  payment_required: boolean
  deposit_required: boolean
  customer_notes: boolean
  guest_booking: boolean
  allow_cancellation: boolean
  allow_rescheduling: boolean
  cancellation_deadline_hours: number
  refund_policy: 'full' | 'deposit_forfeited' | 'none'
  reschedule_deadline_hours: number
  auto_confirm: boolean
  min_lead_time_minutes: number
  max_advance_days: number
  reminder_hours_before: number
  // Restaurant ordering + fulfilment (RestaurantEngine schema).
  order_pickup: boolean
  order_dine_in: boolean
  order_delivery: boolean
  order_curbside: boolean
  delivery_fee: number
  delivery_min_order: number
  auto_accept_orders: boolean
  default_prep_minutes: number
  // VAT / ZATCA e-invoicing (optional per store).
  tax_enabled: boolean
  tax_rate: number
  tax_number: string | null
  legal_name: string | null
  national_address: string | null
}

export interface QrData {
  token: string
  deep_link: string
  image_url: string | null
  download_svg_url: string
  version: number
  analytics: {
    total_scans: number
    last_scanned_at: string | null
    unique_customers: number
    bookings_from_qr: number
  }
}

export interface OnboardingState {
  step: number
  final_step: number
  status: string
  is_published: boolean
  completed: boolean
  blockers: string[]
  progress: {
    has_branch: boolean
    has_services: boolean
    has_staff: boolean
    has_qr: boolean
  }
}

// ---- Restaurant menu (RestaurantEngine) ----------------------------------

export interface MenuOption {
  id: number
  name: string
  name_ar: string
  name_en: string | null
  price_delta: number
  is_available: boolean
}

export interface MenuOptionGroup {
  id: number
  name: string
  name_ar: string
  name_en: string | null
  min_select: number
  max_select: number
  required: boolean
  options: MenuOption[]
}

export interface MenuItem {
  id: number
  name: string
  name_ar: string
  name_en: string | null
  description: string | null
  image: string | null
  price: number
  calories: number | null
  category_id: number | null
  is_available: boolean
  is_active: boolean
  is_featured: boolean
  sort_order: number
  option_groups?: MenuOptionGroup[]
}

export interface MenuCategory {
  id: number
  name: string
  name_ar: string
  name_en: string | null
  image: string | null
  sort_order: number
  is_active: boolean
}
