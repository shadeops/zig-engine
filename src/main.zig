const std = @import("std");

const hapi = @cImport({
    @cInclude("HAPI/HAPI.h");
    @cInclude("raylib.h");
    @cInclude("rlgl.h");
});

const ray = hapi;

fn initMesh() ray.Mesh {
    return ray.Mesh{
        .vertexCount = 0,
        .triangleCount = 0,
        .vertices = null,
        .texcoords = null,
        .texcoords2 = null,
        .normals = null,
        .tangents = null,
        .colors = null,
        .indices = null,
        .animVertices = null,
        .animNormals = null,
        .boneIds = null,
        .boneWeights = null,
        .vaoId = 0,
        .vboId = null,
    };
}
    
const LightLocs = struct {
    enable: i32,
    ltype: i32,
    pos: i32,
    target: i32,
    color: i32,
};

const Light = struct {
    enable: i32 = 1,
    ltype: i32 = 1, // 0 = directional, 1 = point
    pos: [3]f32 = .{ 0, 0, 0 },
    target: [3]f32 = .{ 0, 0, 0 },
    color: [4]f32 = .{ 1, 1, 1, 1 },
    locs: LightLocs,

    fn updateShader(self: @This(), shader: *ray.Shader) void {
        ray.SetShaderValue(shader.*, self.locs.enable, &self.enable, ray.SHADER_UNIFORM_INT);
        ray.SetShaderValue(shader.*, self.locs.ltype, &self.ltype, ray.SHADER_UNIFORM_INT);
        ray.SetShaderValue(shader.*, self.locs.pos, &self.pos, ray.SHADER_UNIFORM_VEC3);
        ray.SetShaderValue(shader.*, self.locs.target, &self.target, ray.SHADER_UNIFORM_VEC3);
        ray.SetShaderValue(shader.*, self.locs.color, &self.color, ray.SHADER_UNIFORM_VEC4);
    }
};


pub fn main() anyerror!void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();

    var session: hapi.HAPI_Session = undefined;
    var result: hapi.HAPI_Result = undefined;
    var cook_status: c_int = undefined;
    var cook_result: hapi.HAPI_Result = undefined;

    if (false) {
        result = hapi.HAPI_CreateInProcessSession(&session);
    } else {
        var hapi_thrift_server_opts = hapi.HAPI_ThriftServerOptions{ .autoClose = 1, .timeoutMs = 3000.0 };
        result = hapi.HAPI_StartThriftNamedPipeServer(&hapi_thrift_server_opts, "hapi", null);
        result = hapi.HAPI_CreateThriftNamedPipeSession(&session, "hapi");
    }

    var cook_options = hapi.HAPI_CookOptions_Create();
    cook_options.maxVerticesPerPrimitive = 3;
    cook_options.checkPartChanges = 0;
    cook_options.cacheMeshTopology = 1;

    result = hapi.HAPI_Initialize(&session, &cook_options, 1, -1, null, null, null, null, null);
    defer result = hapi.HAPI_CloseSession(&session);
    defer result = hapi.HAPI_Cleanup(&session);

    var grid_id: hapi.HAPI_NodeId = undefined;
    var mountain_id: hapi.HAPI_NodeId = undefined;
    var color_id: hapi.HAPI_NodeId = undefined;
    var normal_id: hapi.HAPI_NodeId = undefined;
    var reverse_id: hapi.HAPI_NodeId = undefined;
    result = hapi.HAPI_CreateNode(&session, -1, "Sop/grid", "grid", 0, &grid_id);
    result = hapi.HAPI_CreateNode(&session, -1, "Sop/reverse", "reverse", 0, &reverse_id);
    result = hapi.HAPI_CreateNode(&session, -1, "Sop/normal", "normal", 0, &normal_id);
    result = hapi.HAPI_CreateNode(&session, -1, "Sop/color", "color", 0, &color_id);
    result = hapi.HAPI_CreateNode(&session, -1, "Sop/mountain", "mountain", 0, &mountain_id);
    result = hapi.HAPI_ConnectNodeInput(&session, reverse_id, 0, grid_id, 0);
    result = hapi.HAPI_ConnectNodeInput(&session, normal_id, 0, reverse_id, 0);
    result = hapi.HAPI_ConnectNodeInput(&session, color_id, 0, normal_id, 0);
    result = hapi.HAPI_ConnectNodeInput(&session, mountain_id, 0, color_id, 0);

    result = hapi.HAPI_SetParmIntValue(&session, grid_id, "surftype", 0, 4);
    result = hapi.HAPI_SetParmIntValue(&session, grid_id, "rows", 0, 255);
    result = hapi.HAPI_SetParmIntValue(&session, grid_id, "cols", 0, 255);
    result = hapi.HAPI_SetParmIntValue(&session, normal_id, "type", 0, 0);
    result = hapi.HAPI_SetParmIntValue(&session, normal_id, "reverse", 0, 1);
    result = hapi.HAPI_SetParmIntValue(&session, color_id, "colortype", 0, 1);
    result = hapi.HAPI_SetParmFloatValue(&session, mountain_id, "height", 0, 10);
    result = hapi.HAPI_SetParmFloatValue(&session, mountain_id, "elementsize", 0, 6);
    result = hapi.HAPI_SetParmFloatValue(&session, mountain_id, "roughness", 0, 0.4);
    result = hapi.HAPI_SetParmFloatValue(&session, mountain_id, "lacunarity", 0, 2.01);

    result = hapi.HAPI_CookNode(&session, mountain_id, &cook_options);

    cook_result = hapi.HAPI_Result.HAPI_RESULT_SUCCESS;
    cook_status = hapi.HAPI_STATE_MAX;
    while (cook_status > hapi.HAPI_STATE_MAX_READY_STATE and cook_result == hapi.HAPI_Result.HAPI_RESULT_SUCCESS) {
        cook_result = hapi.HAPI_GetStatus(
            &session,
            hapi.HAPI_StatusType.HAPI_STATUS_COOK_STATE,
            &cook_status,
        );
    }

    var part_id: hapi.HAPI_PartId = 0;

    var geo_info: hapi.HAPI_GeoInfo = undefined;
    result = hapi.HAPI_GetDisplayGeoInfo(&session, mountain_id, &geo_info);
    // std.debug.print("Part count: {}\n", .{geo_info.partCount});

    var part_info: hapi.HAPI_PartInfo = undefined;
    result = hapi.HAPI_GetPartInfo(&session, mountain_id, part_id, &part_info);
    // std.debug.print("Point count: {}\n", .{part_info.pointCount});

    var p_attrib_info: hapi.HAPI_AttributeInfo = undefined;
    result = hapi.HAPI_GetAttributeInfo(
        &session,
        mountain_id,
        part_id,
        "P",
        hapi.HAPI_AttributeOwner.HAPI_ATTROWNER_POINT,
        &p_attrib_info,
    );

    var P_data = try arena.allocator.alloc(f32, @intCast(usize, p_attrib_info.count * p_attrib_info.tupleSize));
    defer arena.allocator.free(P_data);
    result = hapi.HAPI_GetAttributeFloatData(
        &session,
        mountain_id,
        part_id,
        "P",
        &p_attrib_info,
        -1,
        @ptrCast([*c]f32, P_data),
        0,
        p_attrib_info.count,
    );
    
    var n_attrib_info: hapi.HAPI_AttributeInfo = undefined;
    result = hapi.HAPI_GetAttributeInfo(
        &session,
        mountain_id,
        part_id,
        "N",
        hapi.HAPI_AttributeOwner.HAPI_ATTROWNER_POINT,
        &n_attrib_info,
    );

    var N_data = try arena.allocator.alloc(f32, @intCast(usize, n_attrib_info.count * n_attrib_info.tupleSize));
    defer arena.allocator.free(N_data);
    result = hapi.HAPI_GetAttributeFloatData(
        &session,
        mountain_id,
        part_id,
        "N",
        &n_attrib_info,
        -1,
        @ptrCast([*c]f32, N_data),
        0,
        n_attrib_info.count,
    );

    var cd_attrib_info: hapi.HAPI_AttributeInfo = undefined;
    result = hapi.HAPI_GetAttributeInfo(
        &session,
        mountain_id,
        part_id,
        "Cd",
        hapi.HAPI_AttributeOwner.HAPI_ATTROWNER_POINT,
        &cd_attrib_info,
    );

    var clr_uchar_data = try arena.allocator.alloc(u8, @intCast(usize, cd_attrib_info.count * 4));
    defer arena.allocator.free(clr_uchar_data);
    {
        var clr_float_data = try arena.allocator.alloc(f32, @intCast(usize, cd_attrib_info.count * cd_attrib_info.tupleSize));
        defer arena.allocator.free(clr_float_data);
        result = hapi.HAPI_GetAttributeFloatData(
            &session,
            mountain_id,
            part_id,
            "Cd",
            &cd_attrib_info,
            -1,
            @ptrCast([*c]f32, clr_float_data),
            0,
            cd_attrib_info.count,
        );
        var i: usize = 0;
        while (i < cd_attrib_info.count) : (i += 1) {
            clr_uchar_data[i * 4] = @floatToInt(u8, @round(clr_float_data[i * 3] * 255.0));
            clr_uchar_data[i * 4 + 1] = @floatToInt(u8, @round(clr_float_data[i * 3 + 1] * 255.0));
            clr_uchar_data[i * 4 + 2] = @floatToInt(u8, @round(clr_float_data[i * 3 + 2] * 255.0));
            clr_uchar_data[i * 4 + 3] = 255;
        }
    }

    var vtx_list = try arena.allocator.alloc(i32, @intCast(usize, part_info.vertexCount));
    defer arena.allocator.free(vtx_list);
    result = hapi.HAPI_GetVertexList(
        &session,
        mountain_id,
        part_id,
        @ptrCast([*c]i32, vtx_list),
        0,
        part_info.vertexCount,
    );

    //for (N_data) |p,i| {
    //    if (i % 3 == 0 and i>0 ) {
    //        std.debug.print("\n", .{});
    //    }
    //    std.debug.print("{d:0.4}", .{p});
    //    if ( i%3 <2) {
    //        std.debug.print(", ", .{});
    //    }
    //}
    //std.debug.print("\n", .{});

    //for (clr_uchar_data) |p,i| {
    //    if (i % 4 == 0 and i>0 ) {
    //        std.debug.print("\n", .{});
    //    }
    //    std.debug.print("{}", .{p});
    //    if ( i%4 <3) {
    //        std.debug.print(", ", .{});
    //    }
    //}
    //std.debug.print("\n", .{});

    ray.InitWindow(640, 480, "ZigEngine");
    defer ray.CloseWindow();

    ray.SetExitKey(0);
    ray.SetTargetFPS(60);

    var camera: ray.Camera = .{
        .position = .{ .x = 0, .y = 20, .z = 10 },
        .target = .{ .x = 0, .y = 0, .z = 0 },
        .up = .{ .x = 0, .y = 1, .z = 0 },
        .fovy = 35,
        .projection = ray.CAMERA_PERSPECTIVE,
    };

    var shader = ray.LoadShader("resources/base_lighting.vs", "resources/lighting.fs");
    //var shader = ray.LoadShader("resources/base.vs", "resources/base.fs");
    shader.locs[ray.SHADER_LOC_VECTOR_VIEW] = ray.GetShaderLocation(shader, "viewPos");
    shader.locs[ray.SHADER_LOC_MATRIX_MODEL] = ray.GetShaderLocation(shader, "matModel");

    var light_loc = LightLocs{
        .enable = ray.GetShaderLocation(shader, "lights[0].enabled"),
        .ltype = ray.GetShaderLocation(shader, "lights[0].type"),
        .pos = ray.GetShaderLocation(shader, "lights[0].position"),
        .target = ray.GetShaderLocation(shader, "lights[0].target"),
        .color = ray.GetShaderLocation(shader, "lights[0].color"),
    };

    var light: Light = .{
        .locs = light_loc,
        .pos = .{ -20, -20, -15 },
        .color = .{1,1,1,1},
    };
    light.updateShader(&shader);

    var ambient: [4]f32 = .{0.05, 0.05, 0.05, 1.0};
    ray.SetShaderValue(shader, ray.GetShaderLocation(shader, "ambient"), &ambient, ray.SHADER_UNIFORM_VEC4);

    var view_pos: [3]f32 = .{ camera.position.x, camera.position.y, camera.position.z };
    ray.SetShaderValue(shader, shader.locs[ray.SHADER_LOC_VECTOR_VIEW], &view_pos, ray.SHADER_UNIFORM_VEC3);

    var mesh = initMesh();
    mesh.vertexCount = part_info.pointCount;
    mesh.triangleCount = part_info.faceCount;
    mesh.vertices = @ptrCast([*c]f32, P_data);
    mesh.colors = @ptrCast([*c]u8, clr_uchar_data);
    mesh.normals = @ptrCast([*c]f32, N_data);
    mesh.indices = @ptrCast([*c]c_ushort, try arena.allocator.alloc(c_ushort, @intCast(usize, part_info.vertexCount)));
    for (vtx_list) |vtx, i| {
        mesh.indices[i] = @intCast(u16, vtx);
    }

    ray.UploadMesh(&mesh, true);

    var model = ray.LoadModelFromMesh(mesh);
    defer ray.UnloadModelKeepMeshes(model);

    var material = ray.LoadMaterialDefault();
    material.shader = shader;
    material.maps[ray.MATERIAL_MAP_DIFFUSE].color = ray.WHITE;
    model.materials[0] = material;

    ray.SetCameraMode(camera, ray.CAMERA_ORBITAL);

    while (!ray.WindowShouldClose()) {

        {
            result = hapi.HAPI_SetParmFloatValue(&session, mountain_id, "time", 0, @floatCast(f32, ray.GetTime() / 4.0));
            result = hapi.HAPI_CookNode(&session, mountain_id, &cook_options);
            cook_result = hapi.HAPI_Result.HAPI_RESULT_SUCCESS;
            cook_status = hapi.HAPI_STATE_MAX;
            while (cook_status > hapi.HAPI_STATE_MAX_READY_STATE and cook_result == hapi.HAPI_Result.HAPI_RESULT_SUCCESS) {
                cook_result = hapi.HAPI_GetStatus(
                    &session,
                    hapi.HAPI_StatusType.HAPI_STATUS_COOK_STATE,
                    &cook_status,
                );
            }
            result = hapi.HAPI_GetAttributeFloatData(
                &session,
                mountain_id,
                part_id,
                "P",
                &p_attrib_info,
                -1,
                @ptrCast([*c]f32, P_data),
                0,
                p_attrib_info.count,
            );
            result = hapi.HAPI_GetAttributeFloatData(
                &session,
                mountain_id,
                part_id,
                "N",
                &n_attrib_info,
                -1,
                @ptrCast([*c]f32, N_data),
                0,
                n_attrib_info.count,
            );
        }

        ray.UpdateMeshBuffer(mesh, 0, @ptrCast([*c]f32, P_data), 4 * 3 * mesh.vertexCount, 0); // size in bytes, offset in bytes
        ray.UpdateMeshBuffer(mesh, 2, @ptrCast([*c]f32, N_data), 4 * 3 * mesh.vertexCount, 0); // size in bytes, offset in bytes

        ray.ClearBackground(ray.BLACK);
        ray.UpdateCamera(&camera);
        
        view_pos = .{ camera.position.x, camera.position.y, camera.position.z };
        ray.SetShaderValue(shader, shader.locs[ray.SHADER_LOC_VECTOR_VIEW], &view_pos, ray.SHADER_UNIFORM_VEC3);

        ray.BeginDrawing();
        ray.DrawFPS(50, 50);

        ray.BeginMode3D(camera);
        ray.rlDisableBackfaceCulling();
        ray.DrawModel(model, .{ .x = 0, .y = 0, .z = 0 }, 1.0, ray.WHITE);
        ray.EndMode3D();

        ray.EndDrawing();
    }
}
