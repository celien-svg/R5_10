#!/usr/bin/env bash
# Vérifie l'état « seance1-fin » : squelette + PostgreSQL.
# Usage : ./scripts/verify.sh [--no-reset] [--down]
source "$(dirname "$0")/verify-lib.sh"
start_stack "$@"

titre "Les quatre moteurs répondent (TP 1, étape 2.3)"
# Neo4j met 20 à 40 s à démarrer (l'API de la séance 1 ne l'attend pas) : on patiente, comme le TP le demande.
for _ in $(seq 1 45); do docker compose exec -T neo4j cypher-shell -u neo4j -p pixelhub_dev "RETURN 1" > /dev/null 2>&1 && break; sleep 2; done
docker compose exec -T postgres pg_isready -U pixelhub > /dev/null && { PASS=$((PASS+1)); vert "  ✔ PostgreSQL accepting connections"; } || { FAIL=$((FAIL+1)); rouge "  ✘ PostgreSQL"; }
[ "$(docker compose exec -T redis redis-cli ping)" = "PONG" ] && { PASS=$((PASS+1)); vert "  ✔ Redis PONG"; } || { FAIL=$((FAIL+1)); rouge "  ✘ Redis"; }
docker compose exec -T mongo mongosh --quiet -u pixelhub -p pixelhub_dev --authenticationDatabase admin --eval "db.runCommand({ping:1}).ok" | grep -q 1 && { PASS=$((PASS+1)); vert "  ✔ MongoDB ping ok"; } || { FAIL=$((FAIL+1)); rouge "  ✘ MongoDB"; }
docker compose exec -T neo4j cypher-shell -u neo4j -p pixelhub_dev "RETURN 1" > /dev/null 2>&1 && { PASS=$((PASS+1)); vert "  ✔ Neo4j Bolt ok"; } || { FAIL=$((FAIL+1)); rouge "  ✘ Neo4j"; }
curl -sf "http://localhost:${NEO4J_HTTP_PORT:-17474}" > /dev/null && { PASS=$((PASS+1)); vert "  ✔ Neo4j Browser sur 17474"; } || { FAIL=$((FAIL+1)); rouge "  ✘ Neo4j Browser"; }

titre "Séance 1 — PostgreSQL"
http GET /
check "GET / → séance 1 OK" 's == 200 and "séance 1 OK" in b'
http GET /players
check "GET /players → 3 joueurs" 's == 200 and len(j) == 3'
check "Nova / Krayz / Ombre avec leurs pièces" '[(p["pseudo"], p["coins"]) for p in j] == [("Nova",1200),("Krayz",350),("Ombre",90)]'

docker compose --profile app restart api > /dev/null; wait_api
http GET /players
check "Q7 : après redémarrage, pas de doublons" 'len(j) == 3'

http POST /players '{"pseudo":"Pixel","coins":500}'
check "Bonus POST /players → 201, Id attribué par PostgreSQL" 's == 201 and j["id"] == 4'
docker compose exec -T postgres psql -U pixelhub -d pixelhub -tAc 'SELECT count(*) FROM "Players";' | grep -qx 4 \
  && { PASS=$((PASS+1)); vert '  ✔ Les données sont bien dans PostgreSQL (SELECT * FROM "Players")'; } \
  || { FAIL=$((FAIL+1)); rouge "  ✘ Table Players"; }

# Les manipulations des étapes 5 à 7 du TP, rejouées sans terminal interactif (même SQL, mêmes commandes).
pg()     { docker compose exec -T postgres psql -U pixelhub -d pixelhub -tAq "$@"; }
rcli()   { docker compose exec -T redis redis-cli "$@"; }
cypher() { docker compose exec -T neo4j cypher-shell -u neo4j -p pixelhub_dev --format plain "$@"; }
ok()     { PASS=$((PASS+1)); vert "  ✔ $1"; }
ko()     { FAIL=$((FAIL+1)); rouge "  ✘ $1"; }
coins()  { pg -c "SELECT \"Coins\" FROM \"Players\" WHERE \"Pseudo\" = '$1';"; }

titre "TP 1 — étape 5 : la transaction qui protège la monnaie (PostgreSQL)"
out=$(pg <<'SQL'
BEGIN;
UPDATE "Players" SET "Coins" = "Coins" - 100 WHERE "Pseudo" = 'Nova';
UPDATE "Players" SET "Coins" = "Coins" + 100 WHERE "Pseudo" = 'Krayz';
SELECT "Pseudo", "Coins" FROM "Players" WHERE "Pseudo" IN ('Nova', 'Krayz') ORDER BY "Id";
ROLLBACK;
SELECT "Pseudo", "Coins" FROM "Players" WHERE "Pseudo" IN ('Nova', 'Krayz') ORDER BY "Id";
SQL
)
[ "$out" = $'Nova|1100\nKrayz|450\nNova|1200\nKrayz|350' ] && ok "5.1 Atomicité : 1100/450 dans la transaction, 1200/350 après ROLLBACK" || ko "5.1 Atomicité : $out"

# 5.2 : le terminal A garde sa transaction ouverte pendant que le terminal B (et l'API) regardent.
pg > /dev/null 2>&1 <<'SQL' &
BEGIN;
UPDATE "Players" SET "Coins" = "Coins" - 100 WHERE "Pseudo" = 'Nova';
SELECT pg_sleep(8);
ROLLBACK;
SQL
sleep 2
[ "$(coins Nova)" = 1200 ] && ok "5.2 Isolation : le terminal B lit 1200 pendant la transaction de A" || ko "5.2 Isolation (psql)"
http GET /players
check "5.2 Isolation : l'API lit aussi 1200 pour Nova" 's == 200 and [p["coins"] for p in j if p["pseudo"] == "Nova"] == [1200]'
pg -c "SET lock_timeout = '1s'; UPDATE \"Players\" SET \"Coins\" = \"Coins\" + 1 WHERE \"Pseudo\" = 'Nova';" 2>&1 | grep -q 'lock timeout' \
  && ok "5.2 Verrou : l'UPDATE du terminal B attend la fin de la transaction de A" || ko "5.2 Verrou"
wait
[ "$(coins Nova)" = 1200 ] && ok "5.2 Après les deux ROLLBACK, Nova a toujours 1200" || ko "5.2 Nova après ROLLBACK"

out=$(pg 2>&1 <<'SQL'
BEGIN;
ALTER TABLE "Players" ADD CONSTRAINT coins_positifs CHECK ("Coins" >= 0);
UPDATE "Players" SET "Coins" = "Coins" - 100 WHERE "Pseudo" = 'Ombre';
SELECT "Coins" FROM "Players" WHERE "Pseudo" = 'Ombre';
ROLLBACK;
SQL
)
grep -q 'violates check constraint "coins_positifs"' <<< "$out" && grep -q 'current transaction is aborted' <<< "$out" \
  && ok "5.3 Cohérence : CHECK refuse le solde négatif, la transaction est avortée" || ko "5.3 CHECK : $out"
[ "$(pg -c "SELECT count(*) FROM pg_constraint WHERE conname = 'coins_positifs';")" = 0 ] && [ "$(coins Ombre)" = 90 ] \
  && ok "5.3 ROLLBACK annule aussi l'ALTER TABLE : plus de contrainte, Ombre a 90" || ko "5.3 Après ROLLBACK"

titre "TP 1 — étape 6.1 : Redis"
[ "$(rcli SET essai bonjour)" = OK ] && [ "$(rcli GET essai)" = bonjour ] && ok "SET / GET essai" || ko "SET / GET"
rcli SET temporaire vite EX 10 > /dev/null
t=$(rcli TTL temporaire); [ "$t" -ge 9 ] && [ "$t" -le 10 ] && ok "TTL temporaire décroît depuis 10 ($t)" || ko "TTL : $t"
sleep 11
[ "$(rcli TTL temporaire)" = -2 ] && [ -z "$(rcli GET temporaire)" ] && ok "Au bout de 10 s : TTL -2, GET (nil)" || ko "Expiration"
rcli DEL visites > /dev/null; rcli INCR visites > /dev/null; rcli INCR visites > /dev/null
[ "$(rcli INCR visites)" = 3 ] && ok "INCR visites ×3 → 3" || ko "INCR"

titre "TP 1 — étape 6.2 : MongoDB"
out=$(docker compose exec -T mongo mongosh --quiet -u pixelhub -p pixelhub_dev --authenticationDatabase admin essais --eval '
db.jeux.insertOne({ titre: "Hades II", genre: "Roguelike", plateformes: ["PC", "Switch"] });
db.jeux.insertOne({ titre: "Stardew Valley", genre: "Simulation", multijoueur: { joueursMax: 8 } });
const champs = db.jeux.find().toArray().map(d => Object.keys(d).join(","));
print(db.jeux.countDocuments() + "|" + db.jeux.countDocuments({ genre: "Roguelike" }) + "|" + champs.join(";"));
db.dropDatabase();
print(db.getMongo().getDBNames().includes("essais"));')
[ "$out" = $'2|1|_id,titre,genre,plateformes;_id,titre,genre,multijoueur\nfalse' ] \
  && ok "Deux documents aux champs différents, _id ajouté, filtre genre, base essais supprimée" || ko "MongoDB : $out"

titre "TP 1 — étape 6.3 : Neo4j"
cypher "CREATE (ana:Essai {pseudo: 'Ana'}), (bob:Essai {pseudo: 'Bob'}), (cleo:Essai {pseudo: 'Cleo'}),
        (ana)-[:AMI_DE]->(bob), (bob)-[:AMI_DE]->(cleo) RETURN ana, bob, cleo;" > /dev/null
[ "$(cypher "MATCH (:Essai {pseudo: 'Ana'})-[:AMI_DE]->()-[:AMI_DE]->(amiDAmi) RETURN amiDAmi.pseudo;" | tail -1)" = '"Cleo"' ] \
  && ok "Ami d'un ami d'Ana → Cleo" || ko "Ami d'ami"
cypher "MATCH (n:Essai) DELETE n;" 2>&1 | grep -q 'still has relationships' && ok "DELETE seul refusé : le nœud a encore des relations" || ko "DELETE seul"
cypher "MATCH (n:Essai) DETACH DELETE n;" > /dev/null
[ "$(cypher "MATCH (n:Essai) RETURN count(n);" | tail -1)" = 0 ] && ok "DETACH DELETE : plus aucun nœud Essai" || ko "DETACH DELETE"

titre "TP 1 — étape 7 : les données survivent-elles ?"
rcli SET survivant "toujours là ?" > /dev/null
docker compose stop redis postgres > /dev/null 2>&1 && docker compose start redis postgres > /dev/null 2>&1
for _ in $(seq 1 30); do docker compose exec -T postgres pg_isready -U pixelhub > /dev/null 2>&1 && break; sleep 1; done
[ "$(rcli GET survivant)" = "toujours là ?" ] && ok "stop / start : la clé Redis est toujours là" || ko "Redis après stop/start"
docker compose --profile app down > /dev/null 2>&1 && docker compose --profile app up -d > /dev/null 2>&1; wait_api
[ -z "$(rcli GET survivant)" ] && ok "down / up : la clé Redis a disparu (pas de volume)" || ko "Redis après down/up"
[ "$(pg -c 'SELECT count(*) FROM "Players";')" = 4 ] && ok "down / up : les 4 joueurs sont toujours là (volume pg_data)" || ko "PostgreSQL après down/up"

finish "$@"
