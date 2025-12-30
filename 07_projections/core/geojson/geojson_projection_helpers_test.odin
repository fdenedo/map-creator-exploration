package geojson

import "core:fmt"
import "core:mem"
import "core:testing"
import "core:time"

import "../projection"

// ========================================
// BENCHMARK CONFIGURATION
// ========================================

// Toggle verbose output for benchmarks (use -define:BENCHMARK_VERBOSE=false to disable)
BENCHMARK_VERBOSE :: #config(BENCHMARK_VERBOSE, true)

// Number of iterations for timing stability
BENCHMARK_ITERATIONS :: 10

// ========================================
// TEST DATA GENERATORS
// ========================================

// Creates a simple polygon with the specified number of points per ring
@(private = "file")
make_test_polygon :: proc(num_points: int, allocator: mem.Allocator) -> Polygon {
    context.allocator = allocator

    // Create a closed ring with num_points positions
    ring := make([]Position, num_points)
    for i in 0 ..< num_points - 1 {
        angle := f64(i) / f64(num_points - 1) * 360.0
        ring[i] = Position{angle - 180.0, (angle / 4.0) - 45.0, 0}
    }
    ring[num_points - 1] = ring[0]

    rings := make([]LinearRing, 1)
    rings[0] = LinearRing(ring)

    return Polygon{coordinates = rings}
}

// Creates a FeatureCollection with the specified number of polygon features
@(private = "file")
make_test_feature_collection :: proc(
    num_features: int,
    points_per_polygon: int,
    allocator: mem.Allocator,
) -> FeatureCollection {
    context.allocator = allocator

    features := make([]Feature, num_features)
    for i in 0 ..< num_features {
        features[i] = Feature{
            geometry = make_test_polygon(points_per_polygon, allocator),
        }
    }

    return FeatureCollection{features = features}
}

// Creates a MultiPolygon with multiple polygons
@(private = "file")
make_test_multipolygon :: proc(
    num_polygons: int,
    points_per_ring: int,
    allocator: mem.Allocator,
) -> MultiPolygon {
    context.allocator = allocator

    polygons := make([][]LinearRing, num_polygons)
    for i in 0 ..< num_polygons {
        ring := make([]Position, points_per_ring)
        for j in 0 ..< points_per_ring - 1 {
            offset := f64(i * 10)
            angle := f64(j) / f64(points_per_ring - 1) * 360.0
            ring[j] = Position{angle - 180.0 + offset, (angle / 4.0) - 45.0, 0}
        }
        ring[points_per_ring - 1] = ring[0]

        rings := make([]LinearRing, 1)
        rings[0] = LinearRing(ring)
        polygons[i] = rings
    }

    return MultiPolygon{coordinates = polygons}
}

// Creates a LineString with the specified number of points
@(private = "file")
make_test_linestring :: proc(num_points: int, allocator: mem.Allocator) -> LineString {
    context.allocator = allocator

    positions := make([]Position, num_points)
    for i in 0 ..< num_points {
        t := f64(i) / f64(num_points - 1)
        positions[i] = Position{t * 360.0 - 180.0, t * 180.0 - 90.0, 0}
    }

    return LineString{coordinates = positions}
}

// ========================================
// BENCHMARK HELPERS
// ========================================

Benchmark_Result :: struct {
    name:         string,
    iterations:   int,
    total_time:   time.Duration,
    avg_time:     time.Duration,
    min_time:     time.Duration,
    max_time:     time.Duration,
    points_count: int,
    throughput:   f64, // Points per second
}

// Frees all memory allocated by project_geojson
@(private = "file")
free_projected :: proc(projected: GeoJSON_Projected) {
    delete(projected.points)
    for line in projected.lines {
        delete(line)
    }
    delete(projected.lines)
    for poly in projected.polygons {
        for ring in poly {
            delete(ring)
        }
        delete(poly)
    }
    delete(projected.polygons)
}

@(private = "file")
print_benchmark_result :: proc(result: Benchmark_Result) {
    when BENCHMARK_VERBOSE {
        fmt.println("")
        fmt.printfln("┌─ %s", result.name)
        fmt.printfln("│  Iterations: %d", result.iterations)
        fmt.printfln("│  Points:     %d", result.points_count)
        fmt.printfln("│  Avg time:   %v", result.avg_time)
        fmt.printfln("│  Min time:   %v", result.min_time)
        fmt.printfln("│  Max time:   %v", result.max_time)
        fmt.printfln("└  Throughput: %.0f points/sec", result.throughput)
        fmt.println("")
    }
}

@(private = "file")
calculate_stats :: proc(
    times: []time.Duration,
    name: string,
    points_count: int,
) -> Benchmark_Result {
    total: time.Duration = 0
    min_t := times[0]
    max_t := times[0]

    for t in times {
        total += t
        if t < min_t do min_t = t
        if t > max_t do max_t = t
    }

    iterations := len(times)
    avg := total / time.Duration(iterations)
    avg_seconds := time.duration_seconds(avg)
    throughput := f64(points_count) / avg_seconds if avg_seconds > 0 else 0

    return Benchmark_Result{
        name         = name,
        iterations   = iterations,
        total_time   = total,
        avg_time     = avg,
        min_time     = min_t,
        max_time     = max_t,
        points_count = points_count,
        throughput   = throughput,
    }
}

// ========================================
// BENCHMARK TESTS
// ========================================

@(test)
benchmark_project_polygon_small :: proc(t: ^testing.T) {
    allocator, arena, buffer := test_arena_allocator()
    defer cleanup_test_arena(arena, buffer)

    NUM_POINTS :: 100
    polygon := make_test_polygon(NUM_POINTS, allocator)
    geojson := GeoJSON(Geometry(polygon))
    proj := projection.Projection{type = .Orthographic}

    times: [BENCHMARK_ITERATIONS]time.Duration

    // Warmup
    free_projected(project_geojson(geojson, proj))

    // Timed runs
    for i in 0 ..< BENCHMARK_ITERATIONS {
        start := time.now()
        projected := project_geojson(geojson, proj)
        times[i] = time.diff(start, time.now())
        free_projected(projected)
    }

    result := calculate_stats(times[:], "Single Polygon (100 points, Orthographic)", NUM_POINTS)
    print_benchmark_result(result)

    testing.expect(t, result.avg_time > 0, "Benchmark should complete")
}

@(test)
benchmark_project_polygon_large :: proc(t: ^testing.T) {
    allocator, arena, buffer := test_arena_allocator_large()
    defer cleanup_test_arena(arena, buffer)

    NUM_POINTS :: 10_000
    polygon := make_test_polygon(NUM_POINTS, allocator)
    geojson := GeoJSON(Geometry(polygon))
    proj := projection.Projection{type = .Orthographic}

    times: [BENCHMARK_ITERATIONS]time.Duration

    free_projected(project_geojson(geojson, proj))

    for i in 0 ..< BENCHMARK_ITERATIONS {
        start := time.now()
        projected := project_geojson(geojson, proj)
        times[i] = time.diff(start, time.now())
        free_projected(projected)
    }

    result := calculate_stats(times[:], "Single Polygon (10,000 points, Orthographic)", NUM_POINTS)
    print_benchmark_result(result)

    testing.expect(t, result.avg_time > 0, "Benchmark should complete")
}

@(test)
benchmark_project_feature_collection :: proc(t: ^testing.T) {
    allocator, arena, buffer := test_arena_allocator_large()
    defer cleanup_test_arena(arena, buffer)

    NUM_FEATURES :: 100
    POINTS_PER_POLYGON :: 100
    TOTAL_POINTS :: NUM_FEATURES * POINTS_PER_POLYGON

    fc := make_test_feature_collection(NUM_FEATURES, POINTS_PER_POLYGON, allocator)
    geojson := GeoJSON(fc)
    proj := projection.Projection{type = .Orthographic}

    times: [BENCHMARK_ITERATIONS]time.Duration

    free_projected(project_geojson(geojson, proj))

    for i in 0 ..< BENCHMARK_ITERATIONS {
        start := time.now()
        projected := project_geojson(geojson, proj)
        times[i] = time.diff(start, time.now())
        free_projected(projected)
    }

    result := calculate_stats(times[:], "FeatureCollection (100 features, 100 pts each)", TOTAL_POINTS)
    print_benchmark_result(result)

    testing.expect(t, result.avg_time > 0, "Benchmark should complete")
}

@(test)
benchmark_compare_projections :: proc(t: ^testing.T) {
    allocator, arena, buffer := test_arena_allocator_large()
    defer cleanup_test_arena(arena, buffer)

    NUM_POINTS :: 5000
    polygon := make_test_polygon(NUM_POINTS, allocator)
    geojson := GeoJSON(Geometry(polygon))

    // Benchmark Orthographic
    proj_ortho := projection.Projection{type = .Orthographic}
    times_ortho: [BENCHMARK_ITERATIONS]time.Duration

    free_projected(project_geojson(geojson, proj_ortho))
    for i in 0 ..< BENCHMARK_ITERATIONS {
        start := time.now()
        projected := project_geojson(geojson, proj_ortho)
        times_ortho[i] = time.diff(start, time.now())
        free_projected(projected)
    }

    result_ortho := calculate_stats(times_ortho[:], "Orthographic (5000 points)", NUM_POINTS)
    print_benchmark_result(result_ortho)

    // Benchmark Equirectangular
    proj_equirect := projection.Projection{type = .Equirectangular}
    times_equirect: [BENCHMARK_ITERATIONS]time.Duration

    free_projected(project_geojson(geojson, proj_equirect))
    for i in 0 ..< BENCHMARK_ITERATIONS {
        start := time.now()
        projected := project_geojson(geojson, proj_equirect)
        times_equirect[i] = time.diff(start, time.now())
        free_projected(projected)
    }

    result_equirect := calculate_stats(times_equirect[:], "Equirectangular (5000 points)", NUM_POINTS)
    print_benchmark_result(result_equirect)

    // Compare
    when BENCHMARK_VERBOSE {
        ortho_ns := time.duration_nanoseconds(result_ortho.avg_time)
        equirect_ns := time.duration_nanoseconds(result_equirect.avg_time)
        if equirect_ns > 0 {
            ratio := f64(ortho_ns) / f64(equirect_ns)
            if ratio >= 1.0 {
                fmt.printfln("Orthographic is %.2fx slower than Equirectangular", ratio)
            } else {
                fmt.printfln("Orthographic is %.2fx faster than Equirectangular", 1.0 / ratio)
            }
        }
    }

    testing.expect(t, result_ortho.avg_time > 0, "Orthographic benchmark should complete")
    testing.expect(t, result_equirect.avg_time > 0, "Equirectangular benchmark should complete")
}

@(test)
benchmark_multipolygon :: proc(t: ^testing.T) {
    allocator, arena, buffer := test_arena_allocator_large()
    defer cleanup_test_arena(arena, buffer)

    NUM_POLYGONS :: 50
    POINTS_PER_RING :: 100
    TOTAL_POINTS :: NUM_POLYGONS * POINTS_PER_RING

    mp := make_test_multipolygon(NUM_POLYGONS, POINTS_PER_RING, allocator)
    geojson := GeoJSON(Geometry(mp))
    proj := projection.Projection{type = .Orthographic}

    times: [BENCHMARK_ITERATIONS]time.Duration

    free_projected(project_geojson(geojson, proj))

    for i in 0 ..< BENCHMARK_ITERATIONS {
        start := time.now()
        projected := project_geojson(geojson, proj)
        times[i] = time.diff(start, time.now())
        free_projected(projected)
    }

    result := calculate_stats(times[:], "MultiPolygon (50 polygons, 100 pts each)", TOTAL_POINTS)
    print_benchmark_result(result)

    testing.expect(t, result.avg_time > 0, "Benchmark should complete")
}

@(test)
benchmark_linestring :: proc(t: ^testing.T) {
    allocator, arena, buffer := test_arena_allocator_large()
    defer cleanup_test_arena(arena, buffer)

    NUM_POINTS :: 10_000
    ls := make_test_linestring(NUM_POINTS, allocator)
    geojson := GeoJSON(Geometry(ls))
    proj := projection.Projection{type = .Orthographic}

    times: [BENCHMARK_ITERATIONS]time.Duration

    free_projected(project_geojson(geojson, proj))

    for i in 0 ..< BENCHMARK_ITERATIONS {
        start := time.now()
        projected := project_geojson(geojson, proj)
        times[i] = time.diff(start, time.now())
        free_projected(projected)
    }

    result := calculate_stats(times[:], "LineString (10,000 points)", NUM_POINTS)
    print_benchmark_result(result)

    testing.expect(t, result.avg_time > 0, "Benchmark should complete")
}

// ========================================
// SCALING TEST - useful for MapReduce planning
// ========================================

@(test)
benchmark_scaling :: proc(t: ^testing.T) {
    when BENCHMARK_VERBOSE {
        fmt.println("=== Scaling Analysis ===")
        fmt.println("This helps identify where parallelization would help most")
        fmt.println("")
    }

    proj := projection.Projection{type = .Orthographic}
    sizes := [?]int{100, 500, 1_000, 5_000, 10_000, 50_000}

    for size in sizes {
        allocator, arena, buffer := test_arena_allocator_large()

        polygon := make_test_polygon(size, allocator)
        geojson := GeoJSON(Geometry(polygon))

        times: [BENCHMARK_ITERATIONS]time.Duration

        free_projected(project_geojson(geojson, proj))

        for i in 0 ..< BENCHMARK_ITERATIONS {
            start := time.now()
            projected := project_geojson(geojson, proj)
            times[i] = time.diff(start, time.now())
            free_projected(projected)
        }

        result := calculate_stats(times[:], "scaling", size)

        when BENCHMARK_VERBOSE {
            avg_ns := time.duration_nanoseconds(result.avg_time)
            ns_per_point := f64(avg_ns) / f64(size)
            fmt.printfln("%6d points: %10v avg  (%6.1f ns/point, %9.0f pts/sec)",
                size, result.avg_time, ns_per_point, result.throughput)
        }

        cleanup_test_arena(arena, buffer)
    }

    testing.expect(t, true, "Scaling analysis complete")
}

// ========================================
// FEATURE COUNT SCALING - tests parallelization potential across features
// ========================================

@(test)
benchmark_feature_count_scaling :: proc(t: ^testing.T) {
    when BENCHMARK_VERBOSE {
        fmt.println("=== Feature Count Scaling ===")
        fmt.println("Tests how performance scales with number of features (MapReduce candidates)")
        fmt.println("")
    }

    proj := projection.Projection{type = .Orthographic}
    POINTS_PER_FEATURE :: 100
    feature_counts := [?]int{10, 50, 100, 500, 1000}

    for count in feature_counts {
        allocator, arena, buffer := test_arena_allocator_large()

        fc := make_test_feature_collection(count, POINTS_PER_FEATURE, allocator)
        geojson := GeoJSON(fc)
        total_points := count * POINTS_PER_FEATURE

        times: [BENCHMARK_ITERATIONS]time.Duration

        free_projected(project_geojson(geojson, proj))

        for i in 0 ..< BENCHMARK_ITERATIONS {
            start := time.now()
            projected := project_geojson(geojson, proj)
            times[i] = time.diff(start, time.now())
            free_projected(projected)
        }

        result := calculate_stats(times[:], "feature_scaling", total_points)

        when BENCHMARK_VERBOSE {
            avg_ns := time.duration_nanoseconds(result.avg_time)
            ns_per_feature := f64(avg_ns) / f64(count)
            fmt.printfln("%4d features (%6d pts): %10v avg  (%8.1f ns/feature, %9.0f pts/sec)",
                count, total_points, result.avg_time, ns_per_feature, result.throughput)
        }

        cleanup_test_arena(arena, buffer)
    }

    testing.expect(t, true, "Feature count scaling analysis complete")
}

// ========================================
// ARENA ALLOCATORS FOR TESTS
// ========================================

@(private = "file")
test_arena_allocator :: proc() -> (mem.Allocator, ^mem.Arena, []byte) {
    buffer := make([]byte, 64 * 1024) // 64KB
    arena := new(mem.Arena)
    mem.arena_init(arena, buffer)
    return mem.arena_allocator(arena), arena, buffer
}

@(private = "file")
test_arena_allocator_large :: proc() -> (mem.Allocator, ^mem.Arena, []byte) {
    buffer := make([]byte, 16 * 1024 * 1024) // 16MB for larger benchmarks
    arena := new(mem.Arena)
    mem.arena_init(arena, buffer)
    return mem.arena_allocator(arena), arena, buffer
}

@(private = "file")
cleanup_test_arena :: proc(arena: ^mem.Arena, buffer: []byte) {
    free(arena)
    delete(buffer)
}
