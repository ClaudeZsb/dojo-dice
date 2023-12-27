use array::ArrayTrait;
use debug::PrintTrait;
use starknet::{ContractAddress, EthAddress};
// use dojo::database::schema::{SchemaIntrospection, Ty, Enum, serialize_member_type};

#[derive(Model, Drop, Serde)]
struct Game {
    #[key]
    game_id: u256,
    winner: bool,
    white: felt252,
    black: felt252
}

#[derive(Model, Drop, Serde)]
struct PlayerReputation {
    #[key]
    player: felt252,
    total: u32,
    wins: u32,
    cheats: u32,
}
