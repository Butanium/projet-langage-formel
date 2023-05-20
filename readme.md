# Projet langage formel, niveau 3
Par Hugo et Clément

## Structure du projet
Tout le code source est dans le dossier `src/`. Les fichiers de tests sont dans le dossier `tests/`.
### Fichiers sources
- `crc32.c` : fonction de hashage crc32 fournie par l'énoncé
- `hash.c` : implémentation d'une table de hashage fournie par l'énoncé
- `langlex.l` : analyseur lexical du langage
- `lang.y` : analyseur syntaxique du langage et vérification de la spécification

## Compilation du projet
Utiliser `make` ou `make all` pour compiler le projet. Cela créer un fichier `verif_spec` dans le dossier courant.

On peut ensuite utiliser `./verif_spec <fichier>` pour vérifier la spécification contenue dans le fichier `<fichier>`.

## Tests
Pour lancer les tests, utiliser `make test`. Cela va lancer le programme sur tous les fichiers de tests présents dans le dossier `tests/` de la forme `*.prog`.

Exemple de sortie:
```
Testing examples/peterson.prog
parsing successful
Spec 1: Satisfaite
Spec 2: Satisfaite
Spec 3: Non satisfaite
Testing examples/sort.prog
parsing successful
Spec 1: Satisfaite
Spec 2: Non satisfaite
Spec 3: Non satisfaite
Spec 4: Non satisfaite
```