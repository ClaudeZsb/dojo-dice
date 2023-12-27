use starknet::{ContractAddress, EthAddress, secp256_trait::Signature};
use dojo::world::{IWorldDispatcher, IWorldDispatcherTrait};
#[starknet::interface]
trait IActions<ContractState> {
    fn verify(
        self: @ContractState,
        game_id: u256,
        black_address: EthAddress,
        white_address: EthAddress,
        black_number: u8,
        black_commit: u8,
        white_number: u8,
        white_commit: u8,
        black_signature: Signature,
        white_signature: Signature
    );
}
#[starknet::contract]
mod actions {
    use dojo::world::{IWorldDispatcher, IWorldDispatcherTrait};
    use debug::PrintTrait;
    use starknet::{ContractAddress, EthAddress, verify_eth_signature, secp256_trait::Signature};
    use dojo_dice::models::{Game, PlayerReputation};
    use super::IActions;
    use core::poseidon::PoseidonTrait;
    use core::poseidon::poseidon_hash_span;
    use core::array::Span;
    use core::keccak::keccak_u256s_be_inputs;
    use core::hash::{HashStateTrait, HashStateExTrait};

    #[storage]
    struct Storage {
        world_dispatcher: IWorldDispatcher, 
    }

    fn keccak256(mut input: Span<u256>) -> u256 {
        let hash_le = keccak_u256s_be_inputs(input);
        u256 {
            low: core::integer::u128_byte_reverse(hash_le.high),
            high: core::integer::u128_byte_reverse(hash_le.low)
        }
    }

    #[external(v0)]
    impl PlayerActionsImpl of IActions<ContractState> {
        fn verify(
            self: @ContractState,
            game_id: u256,
            black_address: EthAddress,
            white_address: EthAddress,
            black_number: u8,
            black_commit: u8,
            white_number: u8,
            white_commit: u8,
            black_signature: Signature,
            white_signature: Signature
        ) {
            let world = self.world_dispatcher.read();
            let game = get!(world, game_id, (Game));
            assert(game.white == 0 && game.black == 0, 'game id already used');

            assert(black_number < 7 && white_number < 7 && black_commit < 7 && white_commit < 7, 'dice number < 7');

            // let hash_felt252 = PoseidonTrait::new().update(poseidon_hash_span(array![game_id, black_address.into(), white_address.into(), black_number.into(), black_commit.into(), white_number.into(), white_commit.into()].span())).finalize();
            let msgHash = keccak256(array![game_id, black_address.address.into(), white_address.address.into(), black_number.into() * 0x1000000_u256 + black_commit.into() * 0x10000_u256 + white_number.into() * 0x100_u256 + white_commit.into()].span());
            msgHash.print();

            let black = get!(world, black_address, (PlayerReputation));
            let white = get!(world, white_address, (PlayerReputation));

            verify_eth_signature(msgHash, black_signature, black_address);
            verify_eth_signature(msgHash, white_signature, white_address);

            let mut black_wins = black.wins;
            let mut white_wins = white.wins;
            if (black_commit > white_commit) {
                black_wins += 1;
            } else if (black_commit < white_commit) {
                white_wins += 1;
            }

            let mut black_cheats = black.cheats;
            let mut white_cheats = white.cheats;
            if (black_commit != black_number) {
                black_cheats += 1;
            }
            if (white_commit != white_number) {
                white_cheats += 1;
            }


            set!(
                world,
                (
                    PlayerReputation {
                        player: black_address.into(),
                        total: black.total + 1,
                        wins: black_wins,
                        cheats: black_cheats,
                    },
                    PlayerReputation {
                        player: white_address.into(),
                        total: white.total + 1,
                        wins: white_wins,
                        cheats: white_cheats,
                    },
                    Game {
                        game_id: game_id,
                        black: black_address.into(),
                        white: white_address.into(),
                        winner: black_commit > white_commit,
                    }
                )
            );
            
        }
    }
}

#[cfg(test)]
mod tests {
    use debug::PrintTrait;
    use starknet::{ContractAddress, EthAddress, verify_eth_signature, secp256_trait::{Signature, signature_from_vrs}};
    use dojo::test_utils::{spawn_test_world, deploy_contract};
    use dojo_dice::models::{Game, game, PlayerReputation, player_reputation};

    use dojo_dice::actions::actions;
    use starknet::class_hash::Felt252TryIntoClassHash;
    use dojo::world::IWorldDispatcherTrait;
    use dojo::world::IWorldDispatcher;
    use core::array::SpanTrait;
    use core::keccak::keccak_u256s_be_inputs;
    use super::{IActionsDispatcher, IActionsDispatcherTrait, actions::keccak256};

    // helper setup function
    // reusable function for tests
    fn setup_world() -> (IWorldDispatcher, IActionsDispatcher) {
        // models
        let mut models = array![
            game::TEST_CLASS_HASH, player_reputation::TEST_CLASS_HASH
        ];
        // deploy world with models
        let world = spawn_test_world(models);

        // deploy systems contract
        let contract_address = world
            .deploy_contract('salt', actions::TEST_CLASS_HASH.try_into().unwrap());
        let actions_system = IActionsDispatcher { contract_address };

        (world, actions_system)
    }

    #[test]
    #[available_gas(3000000000000000)]
    fn test_verify() {
        // let hash = keccak256(array![0x0000000000000000000000000000000000000000000000000000000000bc614e_u256, 0x0000000000000000000000008d7f03fde1a626223364e592740a233b72395235_u256, 0x0000000000000000000000002a03eb8ca94a87c93ba1f8ea7258deeaf62fa955_u256, 0x0000000000000000000000000000000000000000000000000000000003060405_u256].span());
        // hash.print();
        let hash = 0xb018a69ca7123b8a3cee0f8a7df3fed60936a4c59f8b81bbf587f356a42d6cc7_u256;

        let black: EthAddress = 0x8D7f03FdE1A626223364E592740a233b72395235_u256.into();
        let white: EthAddress = 0x2A03eb8Ca94A87C93BA1f8EA7258DEeaf62fA955_u256.into();

        // r | s | v : 0x7bc08b24e821c2ceafc85e2267ed089e925024749c815560850d78016c6ad4840e2dc2ff8d7ffd94b8d6e510adafad604a9f3306d36c92168c5d29327c4b1e9600
        // ethereum signature v = v + 27 / v = v + CHAIN_ID * 2 + 35
        let blackSig = signature_from_vrs(1, 0x7bc08b24e821c2ceafc85e2267ed089e925024749c815560850d78016c6ad484_u256, 0x0e2dc2ff8d7ffd94b8d6e510adafad604a9f3306d36c92168c5d29327c4b1e96_u256);
        // r | s | v : 0xddb154e06089a7a6a7ebb6bac76465f782ab1ee98273ff34392690f33e549f52059d7c70a39f379170d2ec6e3864da7548dff646578a4dc1ef7f003974f441d601
        let whiteSig = signature_from_vrs(0, 0xddb154e06089a7a6a7ebb6bac76465f782ab1ee98273ff34392690f33e549f52_u256, 0x059d7c70a39f379170d2ec6e3864da7548dff646578a4dc1ef7f003974f441d6_u256);

        // verify_eth_signature(hash, blackSig, black);
        // verify_eth_signature(hash, whiteSig, white);


        let (world, actions_system) = setup_world();

        //system calls
        actions_system.verify(
            12345678_u256,
            black,
            white,
            3,
            6,
            4,
            5,
            blackSig,
            whiteSig,
        );

        //get game
        let black_reputation = get!(world, black, (PlayerReputation));
        let white_reputation = get!(world, white, (PlayerReputation));
        let this_game = get!(world, 12345678_u256, (Game));

        assert(this_game.black == black.into(), 'black should be black');
        assert(this_game.white == white.into(), 'white should be white');
        assert(this_game.winner == true, 'winner should be black');

        assert(black_reputation.total == 1, 'total should be 1');
        assert(white_reputation.total == 1, 'total should be 1');

        assert(black_reputation.wins == 1, 'wins should be 1');
        assert(white_reputation.wins == 0, 'wins should be 0');

        assert(black_reputation.cheats == 1, 'cheats should be 1');
        assert(white_reputation.cheats == 1, 'cheats should be 1');
    }
}