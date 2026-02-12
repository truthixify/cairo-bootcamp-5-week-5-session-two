use starknet::SyscallResultTrait;
use starknet::ContractAddress;

use snforge_std::{
    declare, ContractClassTrait, DeclareResultTrait, spy_events, EventSpyAssertionsTrait,
    start_cheat_caller_address, stop_cheat_caller_address
};

use openzeppelin::token::erc20::interface::{IERC20Dispatcher, IERC20DispatcherTrait};
use counter::{ICounterDispatcher, ICounterDispatcherTrait};
use counter::Counter::{Event, CounterIncremented, CounterDecremented, CounterReset, RewardClaimed, ContractFunded};

const STRK_TOKEN: ContractAddress = 0x04718f5a0Fc34cC1AF16A1cdee98fFB20C31f5cD61D6Ab07201858f4287c938D.try_into().unwrap();
const ADMIN: ContractAddress = 0x021a084dd1ebdf8fa827f2c89f15e95b52975101bbbdd8d2d8711fa8aae84c07.try_into().unwrap();
const USER: ContractAddress = 'USER'.try_into().unwrap();

fn deploy_contract(initial_value: u32) -> ICounterDispatcher {
    let contract = declare("Counter").unwrap_syscall().contract_class();
    let mut constructor_args = array![];
    
    initial_value.serialize(ref constructor_args);
    ADMIN.serialize(ref constructor_args);

    let (contract_address, _) = contract.deploy(@constructor_args).unwrap_syscall();

    ICounterDispatcher { contract_address }
}

#[test]
fn test_constructor() {
    let initial_value = 10;
    let contract = deploy_contract(initial_value);

    let counter = contract.get_counter();
    assert_eq!(counter, initial_value, "Initial value should be set");
    assert_eq!(contract.get_reward_amount(), 0, "Reward should be 0");
}

#[test]
fn test_increment() {
    let contract = deploy_contract(5);

    contract.increment();
    assert_eq!(contract.get_counter(), 6, "Counter should be 6");

    contract.increment();
    assert_eq!(contract.get_counter(), 7, "Counter should be 7");
}

#[test]
fn test_increment_emits_event() {
    let contract = deploy_contract(0);

    let mut spy = spy_events();
    
    contract.increment();

    spy.assert_emitted(@array![
        (
            contract.contract_address,
            Event::CounterIncremented(CounterIncremented { value: 1 })
        )
    ]);
}

#[test]
fn test_decrement() {
    let contract = deploy_contract(10);

    contract.decrement();
    assert_eq!(contract.get_counter(), 9, "Counter should be 9");

    contract.decrement();
    assert_eq!(contract.get_counter(), 8, "Counter should be 8");
}

#[test]
fn test_decrement_emits_event() {
    let contract = deploy_contract(5);

    let mut spy = spy_events();
    
    contract.decrement();

    spy.assert_emitted(@array![
        (
            contract.contract_address,
            Event::CounterDecremented(CounterDecremented { value: 4 })
        )
    ]);
}

#[test]
#[should_panic(expected: 'Counter cannot be negative')]
fn test_decrement_fails_at_zero() {
    let contract = deploy_contract(0);

    contract.decrement();
}

#[test]
#[should_panic(expected: 'Only admin can reset')]
fn test_reset_fails_for_non_admin() {
    let contract = deploy_contract(5);
    
    let non_admin: ContractAddress = 'non_admin'.try_into().unwrap();
    start_cheat_caller_address(contract.contract_address, non_admin);
    
    let amount: u256 = 1000;
    contract.reset(amount);
}

#[test]
#[should_panic(expected: 'Amount must be positive')]
fn test_reset_fails_with_zero_amount() {
    let contract = deploy_contract(5);
    
    start_cheat_caller_address(contract.contract_address, ADMIN);
    contract.reset(0);
}

#[test]
fn test_multiple_operations() {
    let contract = deploy_contract(0);

    contract.increment();
    contract.increment();
    contract.increment();
    assert_eq!(contract.get_counter(), 3, "Counter should be 3");

    contract.decrement();
    assert_eq!(contract.get_counter(), 2, "Counter should be 2");
}

// Fork tests on Sepolia
#[test]
#[fork("sepolia")]
fn test_reset_with_strk_funding() {
    let contract = deploy_contract(5);
    
    let token_dispatcher = IERC20Dispatcher { contract_address: STRK_TOKEN };
    
    let reward_amount: u256 = 1000000000000000000; // 1 STRK (18 decimals)
    
    // Admin approves contract to spend STRK
    start_cheat_caller_address(STRK_TOKEN, ADMIN);
    token_dispatcher.approve(contract.contract_address, reward_amount);
    stop_cheat_caller_address(STRK_TOKEN);
    
    // Admin resets and funds contract
    start_cheat_caller_address(contract.contract_address, ADMIN);
    
    let mut spy = spy_events();
    contract.reset(reward_amount);
    
    stop_cheat_caller_address(contract.contract_address);
    
    // Verify counter reset
    assert_eq!(contract.get_counter(), 0, "Counter should be 0");
    assert_eq!(contract.get_reward_amount(), reward_amount, "Reward should be set");
    
    // Verify events
    spy.assert_emitted(@array![
        (contract.contract_address, Event::CounterReset(CounterReset { value: 0 })),
        (contract.contract_address, Event::ContractFunded(ContractFunded { amount: reward_amount }))
    ]);
}

#[test]
#[fork("sepolia")]
fn test_decrement_to_zero_claims_reward() {
    let contract = deploy_contract(1);
    
    let token_dispatcher = IERC20Dispatcher { contract_address: STRK_TOKEN };
    
    let reward_amount: u256 = 500000000000000000; // 0.5 STRK
    
    // Setup: Admin approves and funds the contract
    start_cheat_caller_address(STRK_TOKEN, ADMIN);
    token_dispatcher.approve(contract.contract_address, reward_amount);
    stop_cheat_caller_address(STRK_TOKEN);
    
    start_cheat_caller_address(contract.contract_address, ADMIN);
    contract.reset(reward_amount);
    stop_cheat_caller_address(contract.contract_address);
    
    // Increment counter
    contract.increment();
    assert_eq!(contract.get_counter(), 1, "Counter should be 1");
    
    // Check contract balance after funding
    let contract_balance_before = token_dispatcher.balance_of(contract.contract_address);
    assert_eq!(contract_balance_before, reward_amount, "Contract should have reward amount");
    
    // Check user balance before claiming
    let user_balance_before = token_dispatcher.balance_of(USER);
    
    // User decrements to zero and claims reward
    start_cheat_caller_address(contract.contract_address, USER);
    
    let mut spy = spy_events();
    contract.decrement();
    
    stop_cheat_caller_address(contract.contract_address);
    
    // Verify counter is zero
    assert_eq!(contract.get_counter(), 0, "Counter should be 0");
    
    // Verify reward was claimed
    assert_eq!(contract.get_reward_amount(), 0, "Reward should be claimed");
    
    // Check user balance after claiming
    let user_balance_after = token_dispatcher.balance_of(USER);
    assert_eq!(user_balance_after, user_balance_before + reward_amount, "User should receive reward");
    
    // Check contract balance is now zero
    let contract_balance_after = token_dispatcher.balance_of(contract.contract_address);
    assert_eq!(contract_balance_after, 0, "Contract balance should be zero");
    
    // Verify reward event
    spy.assert_emitted(@array![
        (contract.contract_address, Event::RewardClaimed(
            RewardClaimed { winner: USER, amount: reward_amount }
        ))
    ]);
}

#[test]
#[fork("sepolia")]
fn test_full_game_cycle() {
    let contract = deploy_contract(3);
    
    let token_dispatcher = IERC20Dispatcher { contract_address: STRK_TOKEN };
    
    let reward_amount: u256 = 1000000000000000000; // 1 STRK
    
    // Round 1: Admin approves and funds
    start_cheat_caller_address(STRK_TOKEN, ADMIN);
    token_dispatcher.approve(contract.contract_address, reward_amount);
    stop_cheat_caller_address(STRK_TOKEN);
    
    start_cheat_caller_address(contract.contract_address, ADMIN);
    contract.reset(reward_amount);
    stop_cheat_caller_address(contract.contract_address);
    
    assert_eq!(contract.get_counter(), 0, "Counter should be 0");
    assert_eq!(contract.get_reward_amount(), reward_amount, "Reward should be set");
    
    // Players increment
    contract.increment();
    contract.increment();
    contract.increment();
    assert_eq!(contract.get_counter(), 3, "Counter should be 3");
    
    // Players decrement
    contract.decrement();
    assert_eq!(contract.get_counter(), 2, "Counter should be 2");
    
    contract.decrement();
    assert_eq!(contract.get_counter(), 1, "Counter should be 1");
    
    // Winner decrements to zero
    start_cheat_caller_address(contract.contract_address, USER);
    contract.decrement();
    stop_cheat_caller_address(contract.contract_address);
    
    assert_eq!(contract.get_counter(), 0, "Counter should be 0");
    assert_eq!(contract.get_reward_amount(), 0, "Reward should be claimed");
}
