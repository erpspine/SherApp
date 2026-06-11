const String kApiBaseUrl = 'https://sher.hanspaulerp.net/api';
const String kBackendOrigin = 'https://sher.hanspaulerp.net';

// Sher ERP App theme colors
// Primary: Sher Gold (Lion Logo color)
const int kGoldColor = 0xFFC9A227;
// Secondary: Sher Navy Blue (Brand text color)
const int kTealColor = 0xFF2F5759;
// Accent: Sher Red (Tagline color - "Conquer the wild")
const int kRedAccent = 0xFFE7333A;
// Dark backgrounds
const int kDarkBg = 0xFF0F172A; // slate-900
const int kDarkCard = 0xFF1E293B; // slate-800
const int kDarkBorder = 0xFF334155; // slate-700

/// Default fuel-tank capacity (litres) used by the driver app's fuel-cycle
/// summary when a vehicle-specific value is not available. With the current
/// fleet this is 180 L; full-tank refuels are assumed, so the litres pumped
/// at the closing fuel-up represent the litres consumed during the cycle.
const double kVehicleFuelCapacityLitres = 180.0;
