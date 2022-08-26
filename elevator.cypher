// CONTRAINTE D'UNICITE DES ETATS (les listes sont supposées triées)
CREATE CONSTRAINT state_key for (n:Etat) REQUIRE (n.haut, n.bas) IS NODE KEY;

//CREATION DE LA RACINE - ETAT INITIAL
CREATE (:Etat:Racine {bas: [], haut:[30, 40, 50, 85]});

// CONSTRUCTION DU GRAPHE DES POSSIBLE
CALL apoc.periodic.commit("MATCH (n:Etat)
WHERE NOT n:Traite
WITH n, [[[30],[]],
[[40],[30]],
[[50],[40]],
[[85],[30, 50]],
[[40, 50],[85]]] AS moves
UNWIND moves AS move
WITH n, move[0] AS descente, move[1] AS montee
WHERE all(poids in descente where poids in n.haut)
AND all(poids in montee where poids in n.bas)
WITH montee, descente, n, apoc.coll.sort(apoc.coll.subtract(n.haut, descente) + montee) AS nouveau_haut,
apoc.coll.sort(apoc.coll.subtract(n.bas, montee) + descente) AS nouveau_bas
MERGE (nouveau:Etat {bas: nouveau_bas, haut: nouveau_haut})
MERGE (n)-[:MOVE_TO {montee: montee, descente: descente}]->(nouveau)
SET n:Traite
WITH count(*) AS limit
RETURN limit", {limit: 41});

// CALCUL DE LA SOLUTION OPTIMALE
MATCH p=(r:Racine)-[:MOVE_TO*]->(dest:Etat)
WHERE size(dest.haut) = 0
WITH relationships(p) AS moves, size(relationships(p)) AS profondeur ORDER BY profondeur ASC
LIMIT 1
UNWIND moves AS move
RETURN move.descente AS descente, move.montee AS montee;

// CALCUL DE LA PROFONDEUR MAXIMALE
MATCH p=(r:Racine)-[:MOVE_TO*]->(dest:Etat)
RETURN size(relationships(p)) AS profondeur ORDER BY profondeur DESC
LIMIT 1

// CALCUL DU FACTEUR DE BRANCHEMENT
MATCH (p:Etat)
RETURN apoc.node.degree(p, "MOVE_TO>") AS facteur_de_branchement
ORDER BY facteur_de_branchement DESC
LIMIT 1;

// HEURISTIQUE
MATCH (n:Etat)
SET n.latitude = 0.0
SET n.longitude = apoc.coll.sum(n.haut + [0])/4000000.0;
// toutes les distances sont ainsi inférieures à 1 mille marin

MATCH ()-[r:MOVE_TO]->()
SET r.distance = 1;

// A STAR - projection mémoire du graphe
CALL gds.graph.project( // si version gds < 2.0 : CALL gds.graph.create(
    'mon_graphe',
    'Etat',
    'MOVE_TO',
    {
        nodeProperties: ['latitude', 'longitude'],
        relationshipProperties: 'distance'
    }
);

// A STAR - streaming de la solution
MATCH (source:Etat:Racine), (target:Etat)
WHERE size(target.haut) = 0
CALL gds.shortestPath.astar.stream('mon_graphe', {
    sourceNode: source,
    targetNode: target,
    latitudeProperty: 'latitude',
    longitudeProperty: 'longitude',
    relationshipWeightProperty: 'distance'
})
YIELD index, sourceNode, targetNode, totalCost, nodeIds, costs, path
RETURN
    index,
    totalCost,
    [nodeId IN nodeIds | [gds.util.asNode(nodeId).haut, gds.util.asNode(nodeId).bas]] AS states,
    costs,
    nodes(path) as path
ORDER BY index