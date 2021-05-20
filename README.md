# Backend de DataPass
[![Rails tests](https://github.com/betagouv/signup-back/actions/workflows/ci.yml/badge.svg)](https://github.com/betagouv/signup-back/actions/workflows/ci.yml)

Les instructions d’installation globale (via VMs / vagrant) se trouvent ici : https://github.com/betagouv/datapass

Pour le développement en local, suivez les instructions ci-dessous:

## Dépendances

* ruby 2.7.3
* postgresql 9.5

## Installation

```sh
bundle install
psql -f db/setup.local.sql
rails db:schema:load
```

## Tests

```sh
bundle exec rspec
# Avec code coverage
COVERAGE=true bundle exec rspec
```

Vous pouvez utiliser [guard](https://github.com/guard/guard) pour lancer les
tests en continue:

```sh
bundle exec guard
```
