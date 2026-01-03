package core

// Coordinate Types
GeoCoord 	:: distinct [2]f32 // (λ, φ) in radians
ScreenVec2 	:: distinct [2]f32 // 2D relative to screen pixels
WorldVec2 	:: distinct [2]f32 // Projected 2D Coordinates
Vector3		:: [3]f32 // Used to represent 3D coords
Matrix4     :: matrix[4, 4]f32
Matrix3     :: matrix[3, 3]f32
