TODO:
[x] 1. Add mesh loading via assimp. Basically take the first mesh, and discard the rest.
[x] 2. Attach icosphere to player hitbox.
[-] 3. Add a system for saving and loading scenes.
[ ] 4. Model an initial scene in Blender. 
[x] 5. Switch to first person camera
[x] 6. Add an enemy, with basic (just run at you) ai
[ ] 7. Add ability to shoot
[ ] 8. Add exploding coins
[ ] 9. Add ammunition and score system
[x] 10. Add dragging objects based on camera vectors
[x] 11. Fix enemy look direction
[x] 12. Resizing the screen
[x] 13. Add crosshair
    - This should be part of the overall HUD layer (obviously)
[x] 14. Fix the model transform buffer so it is a struct that holds both normal and regular transforms
[x] 15. Test if model transform_buffer can be removed from collisions
[ ] 16. Split out the engine and game systems.
[ ] 17. Figure out double click title bar segfaulting
[ ] 18. Add HUD layer


How to handle objects and enemies...
Current implementation works but I want to be able to add and remove enemies easily without adding an excessive burden to memory and than might be kind of difficult.
In addition I want to be able to span i a particle effect when an enemy dies, not sure if that is related.

possibly all of the attributes can be spread out into distinct arrays that havre a cleanup operation and can be structs like {valid: bool, memory: data}
This is basically and entity component system which is potentially a bit suspect.

Right now storing enemies or objects as a value in the array isn't much faster since they fill up the whole cache, so it basicalyl saves a single hashmap lookup which is probably not that expensive.



Particle Effects: 
