class_name CameraController
extends Node3D

enum CAMERA_PIVOT { OVER_SHOULDER, THIRD_PERSON }

@export_node_path var player_path : NodePath
@export var invert_mouse_y := false
@export_range(0.0, 1.0) var mouse_sensitivity := 0.25
@export_range(0.0, 8.0) var joystick_sensitivity := 2.0
@export var tilt_upper_limit := deg_to_rad(-60.0)
@export var tilt_lower_limit := deg_to_rad(60.0)

@onready var camera: Camera3D = $PlayerCamera
@onready var _over_shoulder_pivot: Node3D = $CameraOverShoulderPivot
@onready var _camera_spring_arm: SpringArm3D = $CameraSpringArm
@onready var _third_person_pivot: Node3D = $CameraSpringArm/CameraThirdPersonPivot
@onready var _camera_raycast: RayCast3D = $PlayerCamera/CameraRayCast



var _aim_target : Vector3
var _aim_collider: Node
var _pivot: Node3D
var _current_pivot_type: CAMERA_PIVOT
var _rotation_input: float
var _tilt_input: float
var _mouse_input := false
var _offset: Vector3
var _anchor: CharacterBody3D
var _euler_rotation: Vector3
var _raycast_phantom_cube_under:= false

func _unhandled_input(event: InputEvent) -> void:
    _mouse_input = event is InputEventMouseMotion and Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED
    if _mouse_input:
        _rotation_input = -event.relative.x * mouse_sensitivity
        _tilt_input = -event.relative.y * mouse_sensitivity


func _physics_process(delta: float) -> void:
    if not _anchor:
        return

    _rotation_input += Input.get_action_raw_strength("camera_left") - Input.get_action_raw_strength("camera_right")
    _tilt_input += Input.get_action_raw_strength("camera_up") - Input.get_action_raw_strength("camera_down")

    if invert_mouse_y:
        _tilt_input *= -1

    if _camera_raycast.is_colliding():
        
        _aim_target = _camera_raycast.get_collision_point()
        _aim_collider = _camera_raycast.get_collider()
        #print("camera colliding", _aim_collider.name)
    else:
        _aim_target = _camera_raycast.global_transform * _camera_raycast.target_position
        _aim_collider = null
    if Input.is_action_just_pressed("undo"):
        if Globals.last_block_placed != []:
            Globals.last_block_placed.pop_back().queue_free()
            #Globals.last_block_placed.queue_free()
        
    if Input.is_action_just_pressed("add_block"):
        print("adding block")
        if is_instance_valid(_aim_collider):
            #check if it is in layer 5=17 or 6=32
            if _aim_collider.get_collision_layer() == 17:
                print("Found a normal block")
                place_block_on_top(_aim_collider)
                place_debug_sphere(_aim_target)
            if _aim_collider.get_collision_layer() == 32:
                print("Found a phantom block")
                #start a raycast
                #if it hits another phantom block
                #replace that phantom block with a normal block

                # let us not use raycast, instead worldspace
                var space = get_world_3d().direct_space_state
                var query_phantom = PhysicsRayQueryParameters3D.create(\
                _aim_collider.global_position, _aim_collider.global_position + Vector3(0, -1, 0), pow(2, 6-1))
                var query_normal = PhysicsRayQueryParameters3D.create(\
                _aim_collider.global_position, _aim_collider.global_position + Vector3(0, -1, 0), pow(2, 5-1))
                var result = space.intersect_ray(query_phantom)
                var found_phantom = false
                if result.size() > 0:
                    found_phantom = true
                var result2 = space.intersect_ray(query_normal)
                var found_normal = false
                if result2.size() > 0:
                    found_normal = true
                if found_phantom and ! found_normal:
                    var hit_collider = result.collider
                    print("hit a phantom block under")
                    replace_phatom_with_normal(hit_collider)
                else:
                    print("raycast did not hit")
                    replace_phatom_with_normal(_aim_collider)


    # Set camera controller to current ground level for the character
    var target_position := _anchor.global_position + _offset
    target_position.y = lerp(global_position.y, _anchor._ground_height, 0.1)
    global_position = target_position

    # Rotates camera using euler rotation
    _euler_rotation.x += _tilt_input * delta
    _euler_rotation.x = clamp(_euler_rotation.x, tilt_lower_limit, tilt_upper_limit)
    _euler_rotation.y += _rotation_input * delta

    transform.basis = Basis.from_euler(_euler_rotation)

    camera.global_transform = _pivot.global_transform
    camera.rotation.z = 0

    _rotation_input = 0.0
    _tilt_input = 0.0


func setup(anchor: CharacterBody3D) -> void:
    _anchor = anchor
    _offset = global_transform.origin - anchor.global_transform.origin
    set_pivot(CAMERA_PIVOT.THIRD_PERSON)
    camera.global_transform = camera.global_transform.interpolate_with(_pivot.global_transform, 0.1)
    _camera_spring_arm.add_excluded_object(_anchor.get_rid())
    _camera_raycast.add_exception_rid(_anchor.get_rid())


func set_pivot(pivot_type: CAMERA_PIVOT) -> void:
    if pivot_type == _current_pivot_type:
        return

    match(pivot_type):
        CAMERA_PIVOT.OVER_SHOULDER:
            _over_shoulder_pivot.look_at(_aim_target)
            _pivot = _over_shoulder_pivot
        CAMERA_PIVOT.THIRD_PERSON:
            _pivot = _third_person_pivot

    _current_pivot_type = pivot_type


func get_aim_target() -> Vector3:
    return _aim_target


func get_aim_collider() -> Node:
    if is_instance_valid(_aim_collider):
        return _aim_collider
    else:
        return null

func cube_instance_and_parent(aim_collider):
    var cube_scene = preload("res://BuildingMechanic/cube.tscn")
    var cube = cube_scene.instantiate()
    
    # TODO "bad way to to add this to the world
    var parent_cube = aim_collider.get_parent().get_parent()
    parent_cube.add_child(cube)
    
    return cube
func replace_phatom_with_normal(aim_collider):
    var cube = null

    cube = cube_instance_and_parent(aim_collider)
    
    cube.global_position = aim_collider.global_position
    print("new cube location ", cube.global_position)

    # cheat because the collisions are y=-0.01 so that we can keep the normal blocks on top
    # so we have to add that back here on the normal blocks, since we based of the displaced position of the phantom
    cube.global_position.y += 0.01
    #Globals.last_block_placed = cube
    Globals.last_block_placed.append(cube)
    if Globals.last_block_placed.size() > 5:
        Globals.last_block_placed.pop_front()
func place_block_on_top(aim_collider):
    var cube = cube_instance_and_parent(aim_collider)
    print("new cube location ", cube.global_position)
    cube.global_position = aim_collider.global_position
    cube.global_position.y += 1.0
    Globals.last_block_placed.append(cube)
    if Globals.last_block_placed.size() > 5:
        Globals.last_block_placed.pop_front()
    
func place_debug_sphere(aim_target):
    print("placing debug spehere at ", aim_target)
    var cube_scene = preload("res://BuildingMechanic/debug_sphere.tscn")
    var cube = cube_scene.instantiate()
    
    #var parent_cube = aim_collider.get_parent().get_parent()
    get_tree().get_root().add_child(cube)
    
    cube.global_position = aim_target
    

    var timer = Timer.new()
    timer.connect("timeout",cube.queue_free)
    timer.wait_time = 1
    timer.one_shot = true
    add_child(timer)
    timer.start()
