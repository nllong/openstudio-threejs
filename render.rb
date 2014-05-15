require 'openstudio'

require 'erb'

model = nil
if ARGV[0].nil?
  # generate a simple model for testing purposes

  model = OpenStudio::Model::Model.new
  # space not used
  # space = OpenStudio::Model::Space.new(model)

  verts = OpenStudio::Point3dVector.new
  verts << OpenStudio::Point3d.new(0, 0, 0)
  verts << OpenStudio::Point3d.new(0, 10, 0)
  verts << OpenStudio::Point3d.new(10, 10, 0)
  verts << OpenStudio::Point3d.new(10, 0, 0)

  # floor not used
  # floor = OpenStudio::Model::Surface.new(verts, model)

  verts = OpenStudio::Point3dVector.new
  verts << OpenStudio::Point3d.new(10, 0, 10)
  verts << OpenStudio::Point3d.new(10, 0, 0)
  verts << OpenStudio::Point3d.new(10, 10, 0)
  verts << OpenStudio::Point3d.new(10, 10, 10)
  wall = OpenStudio::Model::Surface.new(verts, model)
else
  puts ARGV[0]
  extension = File.extname(ARGV[0])
  input_path = OpenStudio::Path.new(ARGV[0])
  if extension == '.osm'
    vt = OpenStudio::OSVersion::VersionTranslator.new
    model = vt.loadModel(input_path).get
  elsif extension == '.idf'
    rt = OpenStudio::EnergyPlus::ReverseTranslator.new
    model = rt.loadModel(input_path).get
  elsif extension == '.xml'
    # try sdd
    rt = OpenStudio::SDD::SddReverseTranslator.new
    model = rt.loadModel(input_path)
    if !model.empty?
      model = model.get
    elsif model.empty?
      # try gbXML
      rt = OpenStudio::GbXML::GbXMLReverseTranslator.new
      model = rt.loadModel(input_path)
      unless model.empty?
        model = model.get
      end
    end
  end
end

camera_x = 0
camera_y = 20
camera_z = 100
camera_look_x = 0
camera_look_y = 0
camera_look_z = 0

z = OpenStudio::Vector.new(3)
z[0] = 0
z[1] = 0
z[2] = 1

def get_vertex_index(vertex, all_vertices, scene_geometry, tol = 0.001)
  all_vertices.each_index do |i|
    if OpenStudio.getDistance(vertex, all_vertices[i]) < tol
      return i
    end
  end
  scene_geometry.insert(-1, "geometry.vertices.push( new THREE.Vector3( #{vertex.x}, #{vertex.z}, #{-vertex.y} ) );\n")
  all_vertices << vertex
  (all_vertices.length - 1)
end

all_vertices = []

scene_geometry = "geometry = new THREE.Geometry();\n"
scene_geometry += "var face;\n"
scene_geometry += "geometry.materials = materials;\n"

obj_vertices = ''
obj_faces = ''

model.getSurfaces.each do |surface|

  ext_color = nil
  int_color = nil
  surface_type = surface.surfaceType.upcase
  if surface_type == 'FLOOR'
    ext_color = 'floor_ext_index'
    int_color = 'floor_int_index'
  elsif surface_type == 'WALL'
    ext_color = 'wall_ext_index'
    int_color = 'wall_int_index'
  elsif surface_type == 'ROOFCEILING'
    ext_color = 'roof_ext_index'
    int_color = 'roof_int_index'
  end

  surface_vertices = surface.vertices
  t = OpenStudio::Transformation.alignFace(surface_vertices)
  r = t.rotationMatrix
  t_inv = t.inverse

  site_transformation = OpenStudio::Transformation.new
  planar_surface_group = surface.planarSurfaceGroup
  unless planar_surface_group.empty?
    siteTransformation = planar_surface_group.get.siteTransformation
  end

  surface_vertices = t_inv * surface_vertices
  sub_surface_vertices = OpenStudio::Point3dVectorVector.new
  sub_surfaces = surface.subSurfaces
  sub_surfaces.each do |sub_surface|
    sub_surface_vertices << t_inv * sub_surface.vertices
  end

  triangles = OpenStudio.computeTriangulation(surface_vertices, sub_surface_vertices)
  if triangles.empty?
    puts "Failed to triangulate surface #{surface.name} with #{sub_surfaces.size} sub surfaces"
  end

  triangles.each do |vertices|
    vertices = site_transformation * t * vertices
    normal = site_transformation.rotationMatrix * r * z

    indices = []
    vertices.each do |vertex|
      indices << get_vertex_index(vertex, all_vertices, scene_geometry)
    end
    scene_geometry += "face = new THREE.Face3( #{indices.join(', ')}, new THREE.Vector3( #{normal[0]}, #{normal[2]}, #{-normal[1]} ));\n"
    scene_geometry += "face.materialIndex = #{ext_color};\n"
    scene_geometry += "face.castShadow = true;\n"
    scene_geometry += "face.receiveShadow  = true;\n"
    scene_geometry += "geometry.faces.push(face);\n"

    scene_geometry += "face = new THREE.Face3( #{indices.join(', ')}, new THREE.Vector3( #{normal[0]}, #{normal[2]}, #{-normal[1]} ));\n"
    scene_geometry += "face.materialIndex = #{int_color};\n"
    scene_geometry += "face.castShadow = true;\n"
    scene_geometry += "face.receiveShadow  = true;\n"
    scene_geometry += "geometry.faces.push(face);\n"

    indices.each_index { |i| indices[i] = indices[i] + 1 }
    obj_faces += "f #{indices.join(' ')}\n"
  end

  sub_surfaces.each do |sub_surface|

    sub_surface_vertices = t_inv * sub_surface.vertices
    triangles = OpenStudio.computeTriangulation(sub_surface_vertices, OpenStudio::Point3dVectorVector.new)

    triangles.each do |vertices|
      vertices = site_transformation * t * vertices
      normal = site_transformation.rotationMatrix * r * z

      indices = []
      vertices.each do |vertex|
        indices << get_vertex_index(vertex, all_vertices, scene_geometry)
      end

      scene_geometry += "face = new THREE.Face3( #{indices.join(', ')}, new THREE.Vector3( #{normal[0]}, #{normal[2]}, #{-normal[1]} ));\n"
      scene_geometry += "face.materialIndex = window_ext_index;\n"
      scene_geometry += "face.castShadow = true;\n"
      scene_geometry += "face.receiveShadow  = true;\n"
      scene_geometry += "geometry.faces.push(face);\n"

      scene_geometry += "face = new THREE.Face3( #{indices.join(', ')}, new THREE.Vector3( #{normal[0]}, #{normal[2]}, #{-normal[1]} ));\n"
      scene_geometry += "face.materialIndex = window_int_index;\n"
      scene_geometry += "face.castShadow = true;\n"
      scene_geometry += "face.receiveShadow  = true;\n"
      scene_geometry += "geometry.faces.push(face);\n"

      indices.each_index { |i| indices[i] = indices[i] + 1 }
      obj_faces += "f #{indices.join(' ')}\n"
    end
  end

end
scene_geometry += "mesh = new THREE.Mesh( geometry, new THREE.MeshFaceMaterial(geometry.materials) );\n"
scene_geometry += "mesh.castShadow = true;\n"
scene_geometry += "mesh.receiveShadow = true;\n"
scene_geometry += "scene.add( mesh );\n\n"

# read in template
html_in_path = "#{File.dirname(__FILE__)}/resources/render.html.erb"
html_in = ''
File.open(html_in_path, 'r') do |file|
  html_in = file.read
end

# configure template with variable values
renderer = ERB.new(html_in)
html_out = renderer.result(binding)

# write html file
html_out_path = 'render.html'
File.open(html_out_path, 'w') do |file|
  file << html_out

  # make sure data is written to the disk one way or the other
  begin
    file.fsync
  rescue
    file.flush
  end
end

# write object file
html_out_path = 'render.obj'
File.open(html_out_path, 'w') do |file|

  file << "# OpenStudio OBJ Export\n"
  all_vertices.each do |v|
    file << "v #{v.x} #{v.z} #{-v.y}\n"
  end
  file << obj_faces

  # make sure data is written to the disk one way or the other
  begin
    file.fsync
  rescue
    file.flush
  end
end
