# ninox.d-data

ninox.d-data is a data serialization provider.

## License

The code in this repository is licensed under AGPL-3.0-or-later; for more details see the `LICENSE` file in the repository.

## The core

The core itself contains:
- `SerializerBuffer`: a basic buffer for serialization
- `serialize(value, serializer)` and `deserialize(inp, serializer)` to quickly serialize or deserialize

## Subpackages

Each serialization format is provided via a subpackage:
- `ninox-d_data:json`: provides serialization support from/to JSON