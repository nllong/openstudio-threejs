require 'openstudio'

require 'erb'

model = nil
if ARGV[0].nil?
  #model = OpenStudio::Model::exampleModel

  model = OpenStudio::Model::Model.new
  space = OpenStudio::Model::Space.new(model)
  
  verts = OpenStudio::Point3dVector.new
  verts << OpenStudio::Point3d.new(0,0,0)
  verts << OpenStudio::Point3d.new(0,10,0)
  verts << OpenStudio::Point3d.new(10,10,0)
  verts << OpenStudio::Point3d.new(10,0,0)
  floor = OpenStudio::Model::Surface.new(verts, model)
  
  verts = OpenStudio::Point3dVector.new
  verts << OpenStudio::Point3d.new(10,0,10)
  verts << OpenStudio::Point3d.new(10,0,0)
  verts << OpenStudio::Point3d.new(10,10,0)
  verts << OpenStudio::Point3d.new(10,10,10)
  wall = OpenStudio::Model::Surface.new(verts, model)
else
  puts ARGV[0]
  model = OpenStudio::Model::Model::load( OpenStudio::Path.new(ARGV[0]) ).get
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

def getVertexIndex(vertex, allVertices, sceneGeometry, tol = 0.001)
  allVertices.each_index do |i|
    if OpenStudio::getDistance(vertex, allVertices[i]) < tol
      return i
    end
  end
  sceneGeometry.insert(-1,"geometry.vertices.push( new THREE.Vector3( #{vertex.x}, #{vertex.z}, #{-vertex.y} ) );\n")
  allVertices << vertex
  return (allVertices.length - 1)
end

allVertices = []
sceneGeometry = "geometry = new THREE.Geometry();\n"
sceneGeometry += "var face;\n"
sceneGeometry += "geometry.materials = materials;\n"
model.getSurfaces.each do |surface|

  ext_color = nil
  int_color = nil
  surfaceType = surface.surfaceType.upcase
  if surfaceType == "FLOOR"
    ext_color = "floor_ext_index"
    int_color = "floor_int_index"
  elsif surfaceType == "WALL"
    ext_color = "wall_ext_index"
    int_color = "wall_int_index"  
  elsif surfaceType == "ROOFCEILING"
    ext_color = "roof_ext_index"
    int_color = "roof_int_index"    
  end
  
  surfaceVertices = surface.vertices
  t = OpenStudio::Transformation::alignFace(surfaceVertices)
  r = t.rotationMatrix
  tInv = t.inverse
  
  surfaceVertices = tInv*surfaceVertices
  subSurfaceVertices = OpenStudio::Point3dVectorVector.new
  subSurfaces = surface.subSurfaces
  subSurfaces.each do |subSurface|
    subSurfaceVertices << tInv*subSurface.vertices
  end

  triangles = OpenStudio::computeTriangulation(surfaceVertices, subSurfaceVertices)
  if triangles.empty?
    puts "Failed to triangulate surface #{surface.name} with #{subSurfaces.size} sub surfaces"
  end
  
  triangles.each do |vertices|
    vertices = t*vertices
    normal = r*z

    indices = []
    vertices.each do |vertex|
      indices << getVertexIndex(vertex, allVertices, sceneGeometry)  
    end
    sceneGeometry += "face = new THREE.Face3( #{indices.join(', ')}, new THREE.Vector3( #{normal[0]}, #{normal[2]}, #{-normal[1]} ));\n"
    sceneGeometry += "face.materialIndex = #{ext_color};\n";
    sceneGeometry += "face.castShadow = true;\n";
    sceneGeometry += "face.receiveShadow  = true;\n";
    sceneGeometry += "geometry.faces.push(face);\n"
    
    sceneGeometry += "face = new THREE.Face3( #{indices.join(', ')}, new THREE.Vector3( #{normal[0]}, #{normal[2]}, #{-normal[1]} ));\n"
    sceneGeometry += "face.materialIndex = #{int_color};\n";
    sceneGeometry += "face.castShadow = true;\n";
    sceneGeometry += "face.receiveShadow  = true;\n";
    sceneGeometry += "geometry.faces.push(face);\n"
  end
end
sceneGeometry += "mesh = new THREE.Mesh( geometry, new THREE.MeshFaceMaterial(geometry.materials) );\n"
sceneGeometry += "mesh.castShadow = true;\n"
sceneGeometry += "mesh.receiveShadow = true;\n"
sceneGeometry += "scene.add( mesh );\n\n"
    
# read in template
html_in_path = "#{File.dirname(__FILE__)}/render.html.in"
html_in = ""
File.open(html_in_path, 'r') do |file|
  html_in = file.read
end

# configure template with variable values
renderer = ERB.new(html_in)
html_out = renderer.result(binding)

# write html file
html_out_path = "./render.html"
File.open(html_out_path, 'w') do |file|
  file << html_out
  
  # make sure data is written to the disk one way or the other      
  begin
    file.fsync
  rescue
    file.flush
  end
end
