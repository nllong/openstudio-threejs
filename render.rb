require 'openstudio'

require 'erb'

model = nil
if ARGV[0].nil?
  model = OpenStudio::Model::exampleModel
else
  puts ARGV[0]
  model = OpenStudio::Model::Model::load( OpenStudio::Path.new(ARGV[0]) ).get
end

camera_x = 100
camera_y = 20
camera_z = 100
camera_look_x = 0
camera_look_y = 0
camera_look_z = 0

z = OpenStudio::Vector.new(3)
z[0] = 0
z[1] = 0
z[2] = 1

scene_geometry = ""
model.getSurfaces.each do |surface|

  surfaceVertices = surface.vertices
  t = OpenStudio::Transformation::alignFace(surfaceVertices)
  r = t.rotationMatrix
  tInv = t.inverse
  
  surfaceVertices = tInv*surfaceVertices
  subSurfaceVertices = OpenStudio::Point3dVectorVector.new
  surface.subSurfaces.each do |subSurface|
    subSurfaceVertices << tInv*subSurface.vertices
  end

  triangles = OpenStudio::computeTriangulation(surfaceVertices, subSurfaceVertices)
  if triangles.empty?
    puts surfaceVertices
    puts subSurfaceVertices
  end
  
  triangles.each do |vertices|
    vertices = t*vertices
    normal = r*z
    
    scene_geometry += "var geometry = new THREE.Geometry();\n"
    indices = []
    vertices.each_index do |i|
      indices << i
      vertex = vertices[i]
      scene_geometry += "geometry.vertices.push( new THREE.Vector3( #{vertex.x}, #{vertex.z}, #{vertex.y} ) );\n"
    end
    scene_geometry += "geometry.faces.push( new THREE.Face3( #{indices.join(', ')}, new THREE.Vector3( #{normal[0]}, #{normal[2]}, #{normal[1]} ) ) );\n"
    scene_geometry += "var mesh = new THREE.Mesh( geometry, material );\n"
    scene_geometry += "scene.add( mesh );\n\n"
  end
end

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
