# Starknet Foundry Testing Reference

Advanced testing concepts for snforge beyond basic Counter examples.

## Test Organization

```cairo
// Unit tests: same file as contract
#[cfg(test)]
mod tests {
    use super::MyContract;
}

// Integration tests: tests/ directory
// No #[cfg(test)] needed in tests/ folder
```

Test collection rules:
- `src/`: requires `#[cfg(test)]` module
- `tests/`: all files collected automatically
- Use `tests/` for multi-contract integration scenarios
- Test functions must be annotated with `#[test]`
- Test module names don't matter, only the `#[test]` attribute

## CLI Workflows

```bash
# Run all tests
snforge test

# Run specific test
snforge test test_name

# Filter by pattern
snforge test transfer

# Show detailed output
snforge test -vv          # console output
snforge test -vvv         # + failing traces
snforge test -vvvv        # + all traces

# Run ignored tests
snforge test --ignored
snforge test --include-ignored

# Backtrace on failure
SNFORGE_BACKTRACE=1 snforge test

# Run single test file
snforge test --path tests/integration_test.cairo

# Run tests in parallel (default)
snforge test

# Run tests sequentially
snforge test --max-n-steps 1000000

# Exit on first failure
snforge test --exit-first

# Show gas usage
snforge test --detailed-resources
```

## Assertion Patterns

### Standard Assertions
```cairo
assert(condition, 'error message');
assert_eq!(a, b, "values differ");
assert_ne!(a, b, "should not equal");
assert_lt!(a, b, "a should be less");
assert_le!(a, b, "a should be less or equal");
assert_gt!(a, b, "a should be greater");
assert_ge!(a, b, "a should be greater or equal");
```

### Expected Panics
```cairo
// ByteArray matching (substring)
#[test]
#[should_panic(expected: "insufficient balance")]
fn test_transfer_fail() {
    transfer(1000);  // panics with "Error: insufficient balance"
}

// Felt matching (exact)
#[test]
#[should_panic(expected: 'UNAUTHORIZED')]
fn test_auth_fail() {
    assert(false, 'UNAUTHORIZED');
}

// Tuple matching (multiple messages)
#[test]
#[should_panic(expected: ('ERROR', 'INVALID_AMOUNT'))]
fn test_multi_panic() {
    let mut arr = array!['ERROR', 'INVALID_AMOUNT'];
    panic(arr);
}
```

## Cheatcodes

### Caller Manipulation
```cairo
use snforge_std::{start_cheat_caller_address, stop_cheat_caller_address};

#[test]
fn test_ownership() {
    let contract_address = deploy_contract();
    let owner: ContractAddress = 'owner'.try_into().unwrap();
    
    start_cheat_caller_address(contract_address, owner);
    // All calls now from 'owner'
    dispatcher.admin_function();
    stop_cheat_caller_address(contract_address);
}
```

### Cheat Caller for Multiple Contracts
```cairo
use snforge_std::{CheatSpan, cheat_caller_address};

#[test]
fn test_multi_contract() {
    let user: ContractAddress = 'user'.try_into().unwrap();
    
    // Cheat for specific number of calls
    cheat_caller_address(contract1, user, CheatSpan::TargetCalls(2));
    contract1.call1();  // cheated
    contract1.call2();  // cheated
    contract1.call3();  // not cheated
}
```

### Block Manipulation
```cairo
use snforge_std::{
    start_cheat_block_timestamp, 
    stop_cheat_block_timestamp,
    start_cheat_block_number,
    stop_cheat_block_number
};

#[test]
fn test_time_lock() {
    let contract_address = deploy_contract();
    
    // Set timestamp
    start_cheat_block_timestamp(contract_address, 1000);
    dispatcher.time_locked_function();
    stop_cheat_block_timestamp(contract_address);
    
    // Set block number
    start_cheat_block_number(contract_address, 100);
    dispatcher.block_dependent_function();
    stop_cheat_block_number(contract_address);
}
```

### Cheat Sequencer Address
```cairo
use snforge_std::{start_cheat_sequencer_address, stop_cheat_sequencer_address};

#[test]
fn test_sequencer() {
    let sequencer: ContractAddress = 'sequencer'.try_into().unwrap();
    start_cheat_sequencer_address(contract_address, sequencer);
    dispatcher.sequencer_only_function();
    stop_cheat_sequencer_address(contract_address);
}
```

### Mock Calls
```cairo
use snforge_std::{mock_call, start_mock_call, stop_mock_call};

#[test]
fn test_with_mock() {
    let token_address: ContractAddress = 'token'.try_into().unwrap();
    let mock_balance: u256 = 1000;
    
    // Mock single call
    mock_call(token_address, selector!("balance_of"), mock_balance, 1);
    
    // Or mock multiple calls
    start_mock_call(token_address, selector!("balance_of"), mock_balance);
    // All calls to balance_of return mock_balance
    stop_mock_call(token_address, selector!("balance_of"));
}
```

### Storage Access
```cairo
use snforge_std::{store, load};

#[test]
fn test_storage_manipulation() {
    let contract_address = deploy_contract();
    
    // Read storage
    let value = load(contract_address, selector!("balance"), 1);
    
    // Write storage
    let new_value = array![100];
    store(contract_address, selector!("balance"), new_value.span());
}
```

### L1 Handler Testing
```cairo
use snforge_std::l1_handler_execute;

#[test]
fn test_l1_handler() {
    let contract_address = deploy_contract();
    let from_address = 0x123;
    
    let mut payload = array![];
    payload.append(100);  // amount
    
    l1_handler_execute(
        contract_address,
        selector!("deposit"),
        from_address,
        payload.span()
    ).unwrap();
}
```

## Contract Deployment in Tests

```cairo
use snforge_std::{declare, ContractClassTrait};

#[test]
fn test_deploy() {
    // Declare contract
    let contract = declare("MyContract").unwrap().contract_class();
    
    // Deploy with constructor args using serialize
    let mut constructor_args = array![];
    initial_value.serialize(ref constructor_args);
    admin_address.serialize(ref constructor_args);
    
    let (contract_address, _) = contract.deploy(@constructor_args).unwrap();
    
    // Create dispatcher
    let dispatcher = IMyContractDispatcher { contract_address };
    dispatcher.my_function();
}
```

### Deploy Helper Pattern
```cairo
fn deploy_counter(initial: u32, admin: ContractAddress) -> ICounterDispatcher {
    let contract = declare("Counter").unwrap().contract_class();
    let mut args = array![];
    initial.serialize(ref args);
    admin.serialize(ref args);
    let (addr, _) = contract.deploy(@args).unwrap();
    ICounterDispatcher { contract_address: addr }
}

#[test]
fn test_with_helper() {
    let admin: ContractAddress = 'admin'.try_into().unwrap();
    let counter = deploy_counter(10, admin);
    assert_eq!(counter.get_value(), 10);
}
```

### Deploying with Precalculated Address
```cairo
use snforge_std::{declare, ContractClassTrait, precalculate_address};

#[test]
fn test_precalculate() {
    let contract = declare("Counter").unwrap().contract_class();
    let mut args = array![];
    10_u32.serialize(ref args);
    
    let deployer = starknet::get_contract_address();
    let contract_address = precalculate_address(deployer, 0, @args);
    
    // Use address before deployment
    // ...then deploy
    let (deployed_addr, _) = contract.deploy(@args).unwrap();
    assert_eq!(contract_address, deployed_addr);
}
```

## Testing Events

```cairo
use snforge_std::{spy_events, EventSpyAssertionsTrait};

#[test]
fn test_event_emission() {
    let contract_address = deploy_contract();
    let mut spy = spy_events();
    
    contract.emit_event();
    
    spy.assert_emitted(@array![
        (
            contract_address,
            Event::Transfer(
                Transfer { from: sender, to: recipient, amount: 100 }
            )
        )
    ]);
}
```

### Multiple Events
```cairo
#[test]
fn test_multiple_events() {
    let mut spy = spy_events();
    
    contract.transfer(recipient, 100);
    contract.transfer(recipient2, 200);
    
    spy.assert_emitted(@array![
        (contract_address, Event::Transfer(Transfer { from: sender, to: recipient, amount: 100 })),
        (contract_address, Event::Transfer(Transfer { from: sender, to: recipient2, amount: 200 }))
    ]);
}
```

### Event Filtering
```cairo
use snforge_std::{spy_events, EventSpyTrait, EventSpyAssertionsTrait};

#[test]
fn test_event_filtering() {
    let mut spy = spy_events();
    
    contract.do_something();
    
    // Get events from specific contract
    let events = spy.get_events().emitted_by(contract_address);
    assert_eq!(events.events.len(), 2);
}
```

## Common Mistakes

### Mistake: Not stopping cheatcodes
```cairo
// BAD: affects subsequent tests
start_cheat_caller_address(addr, caller);
dispatcher.function();

// GOOD: always stop
start_cheat_caller_address(addr, caller);
dispatcher.function();
stop_cheat_caller_address(addr);
```

### Mistake: Wrong test module location
```cairo
// BAD: in src/ without cfg
mod tests {  // Won't run
    #[test]
    fn test() {}
}

// GOOD
#[cfg(test)]
mod tests {
    #[test]
    fn test() {}
}
```

### Mistake: Forgetting contract_address in cheatcodes
```cairo
// BAD: missing target
start_cheat_caller_address(new_caller);

// GOOD: specify contract
start_cheat_caller_address(contract_address, new_caller);
```

### Mistake: Using assert_macros in production
```cairo
// BAD: expensive on mainnet
assert_eq!(balance, expected, "balance mismatch");

// GOOD: use standard assert for production
assert(balance == expected, 'balance mismatch');
```

### Mistake: Incorrect constructor argument serialization
```cairo
// BAD: using append for complex types
let mut args = array![];
args.append(my_struct);  // May not work

// GOOD: use serialize
let mut args = array![];
my_value.serialize(ref args);
```

### Mistake: Not using try_into for ContractAddress
```cairo
// BAD: won't compile
let addr: ContractAddress = 'address';

// GOOD
let addr: ContractAddress = 'address'.try_into().unwrap();
```

### Mistake: Reusing spy_events incorrectly
```cairo
// BAD: spy created before contract deployment
let mut spy = spy_events();
let contract = deploy_contract();
contract.emit_event();  // May not capture

// GOOD: spy after deployment
let contract = deploy_contract();
let mut spy = spy_events();
contract.emit_event();
```

## Debugging Tips

1. Use `-vvv` to see execution traces for failing tests
2. Set `SNFORGE_BACKTRACE=1` for panic locations
3. Add `println!` statements (requires `-vv` flag)
4. Check gas usage in test output to identify expensive operations
5. Use `#[ignore]` to isolate problematic tests
6. Use `--exit-first` to stop on first failure
7. Check contract deployment with `declare` errors carefully
8. Verify constructor arguments match contract expectations
9. Use `spy_events()` to debug event emissions
10. Test cheatcodes in isolation to verify behavior

## Test Patterns

### Setup Function Pattern
```cairo
fn setup() -> (ContractAddress, IMyContractDispatcher) {
    let contract = declare("MyContract").unwrap().contract_class();
    let mut args = array![];
    initial_value.serialize(ref args);
    let (addr, _) = contract.deploy(@args).unwrap();
    let dispatcher = IMyContractDispatcher { contract_address: addr };
    (addr, dispatcher)
}

#[test]
fn test_something() {
    let (addr, contract) = setup();
    // test logic
}
```

### Multi-Contract Testing
```cairo
#[test]
fn test_interaction() {
    let user: ContractAddress = 'user'.try_into().unwrap();
    let token = deploy_token();
    let vault = deploy_vault(token.contract_address);
    
    start_cheat_caller_address(token.contract_address, user);
    token.approve(vault.contract_address, 1000);
    stop_cheat_caller_address(token.contract_address);
    
    start_cheat_caller_address(vault.contract_address, user);
    vault.deposit(1000);
    stop_cheat_caller_address(vault.contract_address);
}
```

### Fuzz Testing Pattern
```cairo
// Test with multiple inputs
#[test]
fn test_transfer_amounts() {
    let amounts = array![0, 1, 100, 1000, 999999];
    let mut i = 0;
    loop {
        if i >= amounts.len() {
            break;
        }
        test_single_transfer(*amounts[i]);
        i += 1;
    };
}

fn test_single_transfer(amount: u256) {
    let contract = deploy_contract();
    // test with amount
}
```

### Testing Access Control
```cairo
#[test]
fn test_admin_only() {
    let admin: ContractAddress = 'admin'.try_into().unwrap();
    let user: ContractAddress = 'user'.try_into().unwrap();
    let contract = deploy_with_admin(admin);
    
    // Admin can call
    start_cheat_caller_address(contract.contract_address, admin);
    contract.admin_function();
    stop_cheat_caller_address(contract.contract_address);
    
    // User cannot call
    start_cheat_caller_address(contract.contract_address, user);
    // Should panic
}

#[test]
#[should_panic(expected: 'Only admin')]
fn test_non_admin_fails() {
    let admin: ContractAddress = 'admin'.try_into().unwrap();
    let user: ContractAddress = 'user'.try_into().unwrap();
    let contract = deploy_with_admin(admin);
    
    start_cheat_caller_address(contract.contract_address, user);
    contract.admin_function();
}
```

### Testing State Transitions
```cairo
#[test]
fn test_state_machine() {
    let contract = deploy_contract();
    
    // Initial state
    assert_eq!(contract.get_state(), State::Pending);
    
    // Transition 1
    contract.activate();
    assert_eq!(contract.get_state(), State::Active);
    
    // Transition 2
    contract.pause();
    assert_eq!(contract.get_state(), State::Paused);
    
    // Transition 3
    contract.resume();
    assert_eq!(contract.get_state(), State::Active);
}
```

### Testing with Time
```cairo
use snforge_std::{start_cheat_block_timestamp, stop_cheat_block_timestamp};

#[test]
fn test_time_based_logic() {
    let contract = deploy_contract();
    let start_time = 1000;
    
    start_cheat_block_timestamp(contract.contract_address, start_time);
    contract.start_auction();
    
    // Fast forward 1 hour
    start_cheat_block_timestamp(contract.contract_address, start_time + 3600);
    contract.end_auction();
    stop_cheat_block_timestamp(contract.contract_address);
}
```

## Performance Tips

- Keep unit tests in `src/` for faster compilation
- Use `#[ignore]` for slow integration tests during development
- Minimize contract deployments per test
- Reuse dispatchers when testing same contract multiple times
- Avoid unnecessary cheatcode start/stop cycles
- Use helper functions to reduce code duplication
- Group related tests in same file to share setup code
- Consider using `--exit-first` during development
- Profile tests with `--detailed-resources` to find bottlenecks

## Advanced Topics

### Testing Upgradeable Contracts
```cairo
#[test]
fn test_upgrade() {
    let v1 = declare("ContractV1").unwrap().contract_class();
    let v2 = declare("ContractV2").unwrap().contract_class();
    
    let (addr, _) = v1.deploy(@array![]).unwrap();
    let proxy = IUpgradeableDispatcher { contract_address: addr };
    
    // Use v1
    proxy.function_v1();
    
    // Upgrade to v2
    proxy.upgrade(v2.class_hash);
    
    // Use v2
    proxy.function_v2();
}
```

### Testing with Safe Dispatcher
```cairo
use counter::{ICounterSafeDispatcher, ICounterSafeDispatcherTrait};

#[test]
fn test_safe_dispatcher() {
    let contract = deploy_contract(0);
    let safe = ICounterSafeDispatcher { contract_address: contract.contract_address };
    
    match safe.decrement() {
        Result::Ok(_) => panic!("Should have failed"),
        Result::Err(panic_data) => {
            assert_eq!(*panic_data.at(0), 'Counter cannot be negative');
        }
    };
}
```

### Testing Reentrancy Guards
```cairo
#[test]
#[should_panic(expected: 'Reentrant call')]
fn test_reentrancy_protection() {
    let attacker = deploy_attacker();
    let victim = deploy_victim();
    
    start_cheat_caller_address(victim.contract_address, attacker.contract_address);
    victim.vulnerable_function();
}
```

### Fork Testing
```cairo
// In Scarb.toml:
// [[tool.snforge.fork]]
// name = "mainnet"
// url = "https://starknet-mainnet.public.blastapi.io"
// block_id.number = "123456"

use snforge_std::fork;

#[test]
#[fork("mainnet")]
fn test_on_fork() {
    // Test against mainnet state at block 123456
    let token = ITokenDispatcher { contract_address: MAINNET_TOKEN_ADDRESS };
    let balance = token.balance_of(SOME_ADDRESS);
    assert(balance > 0, 'Should have balance');
}
```

## Reference

Official docs: https://foundry-rs.github.io/starknet-foundry/
