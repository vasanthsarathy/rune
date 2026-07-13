package main
import c "../../canvas"

setup :: proc() {
	c.size(900, 900)
}

draw :: proc() {
	c.background(255, 255, 255)
c.fill(0,0,0)
c.circle(200,200,50)
}

main :: proc() {
	c.run(setup, draw)
}
