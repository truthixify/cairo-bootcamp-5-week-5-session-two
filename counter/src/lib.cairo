#[starknet::interface]
pub trait ICounter<TContractState> {
    fn increment(ref self: TContractState);
    fn decrement(ref self: TContractState);
    fn reset(ref self: TContractState, amount: u256);
    fn get_counter(self: @TContractState) -> u32;
    fn get_reward_amount(self: @TContractState) -> u256;
}

#[starknet::contract]
pub mod Counter {
    use starknet::storage::{StoragePointerReadAccess, StoragePointerWriteAccess};
    use starknet::{ContractAddress, get_caller_address, get_contract_address};
    use openzeppelin::token::erc20::interface::{IERC20Dispatcher, IERC20DispatcherTrait};

    // STRK token address on Starknet
    const STRK_TOKEN: ContractAddress = 0x04718f5a0Fc34cC1AF16A1cdee98fFB20C31f5cD61D6Ab07201858f4287c938D.try_into().unwrap();

    #[storage]
    struct Storage {
        counter: u32,
        admin: ContractAddress,
        reward_amount: u256,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    pub enum Event {
        CounterIncremented: CounterIncremented,
        CounterDecremented: CounterDecremented,
        CounterReset: CounterReset,
        RewardClaimed: RewardClaimed,
        ContractFunded: ContractFunded,
    }

    #[derive(Drop, starknet::Event)]
    pub struct CounterIncremented {
        pub value: u32,
    }

    #[derive(Drop, starknet::Event)]
    pub struct CounterDecremented {
        pub value: u32,
    }

    #[derive(Drop, starknet::Event)]
    pub struct CounterReset {
        pub value: u32,
    }

    #[derive(Drop, starknet::Event)]
    pub struct RewardClaimed {
        pub winner: ContractAddress,
        pub amount: u256,
    }

    #[derive(Drop, starknet::Event)]
    pub struct ContractFunded {
        pub amount: u256,
    }

    #[constructor]
    fn constructor(ref self: ContractState, initial_value: u32, admin: ContractAddress) {
        self.counter.write(initial_value);
        self.admin.write(admin);
        self.reward_amount.write(0);
    }

    #[abi(embed_v0)]
    impl CounterImpl of super::ICounter<ContractState> {
        fn increment(ref self: ContractState) {
            let current = self.counter.read();
            let new_value = current + 1;
            self.counter.write(new_value);

            self.emit(CounterIncremented { value: new_value });
        }

        fn decrement(ref self: ContractState) {
            let current = self.counter.read();

            assert(current > 0, 'Counter cannot be negative');

            let new_value = current - 1;
            self.counter.write(new_value);

            self.emit(CounterDecremented { value: new_value });

            // If counter reaches zero, reward the caller
            if new_value == 0 {
                let winner = get_caller_address();
                let reward = self.reward_amount.read();

                if reward > 0 {
                    
                    let token_dispatcher = IERC20Dispatcher { contract_address: STRK_TOKEN };

                    // Transfer reward to winner
                    token_dispatcher.transfer(winner, reward);

                    self.emit(RewardClaimed { winner, amount: reward });

                    // Reset reward amount
                    self.reward_amount.write(0);
                }
            }
        }

        fn reset(ref self: ContractState, amount: u256) {
            let caller = get_caller_address();
            let admin = self.admin.read();

            assert(caller == admin, 'Only admin can reset');
            assert(amount > 0, 'Amount must be positive');

            // Transfer STRK from admin to contract
            
            let token_dispatcher = IERC20Dispatcher { contract_address: STRK_TOKEN };
            let this_contract = get_contract_address();

            // Admin must have approved this contract before calling reset
            token_dispatcher.transfer_from(caller, this_contract, amount);

            // Set reward amount
            self.reward_amount.write(amount);

            self.counter.write(0);
            self.emit(CounterReset { value: 0 });
            self.emit(ContractFunded { amount });
        }

        fn get_counter(self: @ContractState) -> u32 {
            self.counter.read()
        }

        fn get_reward_amount(self: @ContractState) -> u256 {
            self.reward_amount.read()
        }
    }
}
