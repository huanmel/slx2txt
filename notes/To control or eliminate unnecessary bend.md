To control or eliminate unnecessary bendpoints in the Eclipse Layout Kernel (ELK), use the [Add Unnecessary Bendpoints](https://eclipse.dev/elk/reference/options/org-eclipse-elk-layered-unnecessaryBendpoints.html) option. To force a completely straight line between source and target, use the [Edge Layout Strategy](https://eclipse.dev/elk/reference/options/org-eclipse-elk-vertiflex-layoutStrategy.html). [1, 2] 
Check the specific options available to help you clean up or limit bendpoints:
## 1. Hide Unnecessary Bendpoints (Layered Algorithm)
If ELK is generating extra, unwanted bendpoints during polyline routing: [3, 4] 

* Option: org.eclipse.elk.layered.unnecessaryBendpoints
* Values: true / false
* Default: false
* Details: By default, ELK optimizes edge routings by eliminating extra corners. Setting this to true forces the algorithm to keep dummy routing segments even if the edge doesn't change direction. [1, 3] 

## 2. Prioritize Straight Edges
If you want to enforce direct connections (straight lines) rather than allowing corners:

* Option: org.eclipse.elk.vertiflex.layoutStrategy
* Values: straight / bend
* Details: Setting this to straight prioritizes straight-line node drawings. Nodes will be re-ordered to ensure that direct connections do not result in overlapping. [2] 

## 3. Force Fixed Layouts (Pre-defined Routes)
If you already know the precise path an edge should take and want to stop ELK from adding its own corner logic:

* Option: org.eclipse.elk.bendPoints
* Values: List of coordinate points $(x, y)$
* Details: Using the fixed layout algorithm, you can specify a pre-defined routing for an edge. The chain must include the source point, your exact bendpoints, and the target point. [5, 6] 

## 4. Remove Edge Routing
To tell ELK to stop trying to route around shapes and just connect the points:

* Option: org.eclipse.elk.edgeRouting
* Values: ORTHOGONAL / POLYLINE / SPLINE / STRAIGHT
* Details: Switching this to STRAIGHT will strictly bypass the bendpoint routing systems and connect ports directly. [5, 6, 7, 8] 


[1] [https://eclipse.dev](https://eclipse.dev/elk/reference/options/org-eclipse-elk-layered-unnecessaryBendpoints.html)
[2] [https://eclipse.dev](https://eclipse.dev/elk/reference/options/org-eclipse-elk-vertiflex-layoutStrategy.html)
[3] [https://dagobertgans.github.io](https://dagobertgans.github.io/docgen/_pages/org-eclipse-elk-layered-unnecessaryBendpoints.html)
[4] [https://dagobertgans.github.io](https://dagobertgans.github.io/docgen/_pages/org-eclipse-elk-layered.html)
[5] [https://eclipse.dev](https://eclipse.dev/elk/reference/options/org-eclipse-elk-bendPoints.html)
[6] [https://eclipse.dev](https://eclipse.dev/elk/reference/options/org-eclipse-elk-stress-dimension.html)
[7] [https://eclipse.dev](https://eclipse.dev/elk/reference/options/org-eclipse-elk-position.html)
[8] [https://www.arista.com](https://www.arista.com/en/um-eos/eos-spanning-tree-protocol)


No, ELK does not have a direct layout option like maxBendpoints to strictly cap the count to an exact integer (e.g., "maximum 2 bendpoints").
Instead, the number of bendpoints is an emergent outcome of the layout algorithm's execution phases. You can, however, indirectly limit or minimize them by tuning specific parameters that penalize bends, restrict routing behavior, or optimize node placement.
## 1. Choose a Routing Style with Structural Limits
The most reliable way to limit bendpoints is to alter the [Edge Routing style](https://eclipse.dev/elk/reference/options/org-eclipse-elk-bendPoints.html) entirely:

* STRAIGHT: Forces zero bendpoints. Edges will be direct point-to-point lines, completely bypassing bend calculations.
* ORTHOGONAL: Structurally caps polyline routing segments. In many configurations (like the layered Sugiyama layout), an edge is restricted to exactly three segments (one vertical and two horizontal), meaning it will naturally yield a maximum of 2 bendpoints per edge. [1] 

## 2. Disable Unnecessary Splitting (Layered Layout)
If using ELK Layered, ensure the layout isn't creating artificial bendpoints when edges cross hierarchies or follow long paths:

* Set org.eclipse.elk.layered.unnecessaryBendpoints to false.
* This tells ELK to strictly prune out any bendpoints where the edge travels straight through an intermediate layer without altering its direction. [2] 

## 3. Activate "Straightening" Optimization Processors
You can configure the node placement sub-phase to aggressively straighten lines, which minimizes the overall number of bends created:

* Use org.eclipse.elk.layered.nodePlacement.bk.edgeStraightening.
* Set it to NONE or ALL depending on your layout mode to let the Brandes-Köpf algorithm actively push nodes into straight vertical/horizontal lines rather than prioritizing uniform balancing. [3] 

## 4. Adjust the Sloped Edge Zone
For polyline routers, nodes that sit right at the boundary edge of a layout layer can force sudden, awkward corner paths:

* Adjust org.eclipse.elk.layered.edgeRouting.polyline.slopedEdgeZoneWidth.
* Increasing this width allows the router to maintain a straight diagonal slope longer instead of breaking the path with extra bendpoints. [4] 

## Summary Configuration Example (JSON)

{
  "id": "root",
  "layoutOptions": {
    "org.eclipse.elk.algorithm": "layered",
    "org.eclipse.elk.edgeRouting": "STRAIGHT", 
    "org.eclipse.elk.layered.unnecessaryBendpoints": "false"
  }
}

If you are using a specific routing engine (such as libavoid or Graphviz Dot), please let me know. I can provide the exact angle penalty or weight options available for that specific ecosystem to help flatten your paths.

[1] [https://rtsys.informatik.uni-kiel.de](https://rtsys.informatik.uni-kiel.de/~biblio/downloads/theses/thw-bt.pdf)
[2] [https://eclipse.dev](https://eclipse.dev/elk/reference/options/org-eclipse-elk-layered-unnecessaryBendpoints.html)
[3] [https://eclipse.dev](https://eclipse.dev/elk/reference/options.html)
[4] [https://eclipse.dev](https://eclipse.dev/elk/reference/options/org-eclipse-elk-layered-edgeRouting-polyline-slopedEdgeZoneWidth.html)


In [MathWorks Stateflow](https://www.mathworks.com/products/stateflow.html), transition lines do not support multiple arbitrary geometric bendpoints because Stateflow transitions are drawn as mathematical arcs governed strictly by a single MidPoint coordinate. [1, 2] 
When attempting to convert a layout algorithm (like ELK) into Stateflow, you cannot natively pass a chain of multi-segmented points. To bypass this structural limitation and successfully reproduce multi-bend routing, utilize the following options:
## 1. Connective Junctions (The Canonical Solution)
To force a multi-segmented layout path, you must split your single logical transition into multiple sequential transition segments by placing Connective Junctions at each layout bendpoint. [3] 

* Mechanism: Every bendpoint generated by ELK becomes a circular Stateflow.Junction object.
* Execution: Route the transition from State A $\rightarrow$ Junction 1 $\rightarrow$ Junction 2 $\rightarrow$ State B.
* API Property: Set the condition text (e.g., [condition]) on the first segment. Keep the trailing segments completely empty so execution flows through them instantaneously within the same evaluation step. [3, 4, 5] 

[State A] ---> (Junction 1) ---> (Junction 2) ---> [State B]

## 2. Map Multi-Bend Lines to Arc Midpoints
If you do not want to inject junctions into your model logic, you must simplify the ELK polyline layout down to Stateflow's single-point paradigm. You can mathematically calculate the single MidPoint property via the [Stateflow API](https://www.mathworks.com/help/stateflow/programmatic-interface.html): [6] 

* Calculate Chord Vector: Find the straight vector connecting the source state anchor to the destination state anchor.
* Define Sagitta (Bulge): Compute the maximum perpendicular offset distance of your ELK polyline relative to that straight chord vector.
* Apply MidPoint: Use the API to push the target MidPoint vector:

% MATLAB API Example
tx = find(chart, '-isa', 'Stateflow.Transition');
tx.MidPoint = [X_coordinate, Y_coordinate]; 

* This transforms the polyline into a smooth curved arc that clears intervening substates.

## 3. Restructure Hierarchies via Atomic Subcharts
If your ELK bendpoints are being generated primarily to snake around substate boundaries within a huge, dense diagram, abstract the complexity away entirely:

* Convert complex substates into Atomic Subcharts.
* This creates modular, encapsulated clean black-boxes. The top-level diagram will require significantly fewer transitions, allowing you to use simple straight lines (org.eclipse.elk.edgeRouting: "STRAIGHT") instead of relying on intricate layout paths.

## 4. Switch ELK to Orthogonal Routing
To match Stateflow's tendency to snap lines cleanly around states, enforce strict constraints in ELK prior to parsing the layout coordinates:

* Set org.eclipse.elk.edgeRouting to ORTHOGONAL.
* This yields predictable 90-degree stair-step line structures that map beautifully to coordinate grid junctions if you pursue Option 1. [7] 

Are you building this state machine translation tool programmatically using the MATLAB API/M-script, or are you generating Simulink/Stateflow MDL/SLX XML files directly? Let me know so I can share the exact programmatic code structures for placing junctions. [8] 

[1] [https://la.mathworks.com](https://la.mathworks.com/matlabcentral/answers/1599209-handling-of-large-co-ordinates-in-state-flow)
[2] [https://www.stateworks.com](https://www.stateworks.com/technology/understanding-state-machines/)
[3] [https://www.mathworks.com](https://www.mathworks.com/help/stateflow/gs/get-started-flowchart-chart.html)
[4] [https://dokumen.pub](https://dokumen.pub/stateflow-api.html)
[5] [https://www.youtube.com](https://www.youtube.com/watch?v=cXnT5-zY3YI&vl=en)
[6] [https://www.mathworks.com](https://www.mathworks.com/help/stateflow/programmatic-interface.html)
[7] [https://kolegite.com](https://kolegite.com/EE_library/books_and_lectures/MATLAB/Stateflow.pdf)
[8] [https://www.youtube.com](https://www.youtube.com/watch?v=RIpzPqAMu4s)
