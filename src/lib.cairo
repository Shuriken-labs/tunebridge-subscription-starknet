use starknet::storage::{
    Map, MutableVecTrait, StoragePathEntry, StoragePointerReadAccess, StoragePointerWriteAccess,
    Vec, VecTrait,
};
use starknet::{ContractAddress, get_block_timestamp, get_caller_address};


/// Interface representing `HelloContract`.
/// This interface allows modification and retrieval of the contract balance.
#[starknet::interface]
pub trait IERC20<TContractState> {
    fn get_name(self: @TContractState) -> felt252;
    fn get_symbol(self: @TContractState) -> felt252;
    fn get_decimals(self: @TContractState) -> u8;
    fn get_total_supply(self: @TContractState) -> felt252;
    fn balance_of(self: @TContractState, account: ContractAddress) -> felt252;
    fn allowance(
        self: @TContractState, owner: ContractAddress, spender: ContractAddress,
    ) -> felt252;
    fn transfer(ref self: TContractState, recipient: ContractAddress, amount: felt252);
    fn transfer_from(
        ref self: TContractState, sender: ContractAddress, recipient: ContractAddress, amount: u256,
    );
    fn approve(ref self: TContractState, spender: ContractAddress, amount: felt252);
    fn increase_allowance(ref self: TContractState, spender: ContractAddress, added_value: felt252);
    fn decrease_allowance(
        ref self: TContractState, spender: ContractAddress, subtracted_value: felt252,
    );
}

#[derive(Clone, Serde, Drop, Copy)]
pub struct UserState {
    amount: u256,
    date: u64,
    user_address: ContractAddress,
}

#[starknet::interface]
pub trait ITuneBridge<TContractState> {
    fn fetch_user(self: @TContractState, user_address: ContractAddress) -> UserState;
    fn subscribe(ref self: TContractState, tier_index: u64);
    fn get_subscription_amount(self: @TContractState) -> Array<u256>;
    fn get_subscription_token(self: @TContractState) -> ContractAddress;
    fn add_subscription_amount(ref self: TContractState, amount: u256);
    fn adjust_subscription_token(
        ref self: TContractState, new_token: ContractAddress, index: u64, new_amount: u256,
    );
}

/// Simple contract for managing balance.
#[starknet::contract]
mod TuneBridge {
    // use starknet::storage::MutableVecTrait;
    use super::{
        *, IERC20Dispatcher, IERC20DispatcherTrait, MutableVecTrait, StoragePointerReadAccess,
        StoragePointerWriteAccess, UserState, Vec, VecTrait,
    };


    #[derive(Copy, Drop, Serde, starknet::Store)]
    pub struct ISubscription {
        amount: u256,
        date: u64,
    }

    #[storage]
    struct Storage {
        subscription_tier: Vec<u256>,
        subscription: Map<ContractAddress, ISubscription>,
        owner: ContractAddress,
        token_address: ContractAddress,
        token: IERC20Dispatcher,
    }

    #[constructor]
    fn constructor(
        ref self: ContractState,
        _token_address: ContractAddress,
        _subscription_amount_1: u256,
        _subscription_amount_2: u256,
    ) {
        self.owner.write(get_caller_address());
        self.token_address.write(_token_address);
        let mut subscription = self.subscription_tier;
        subscription.push(_subscription_amount_1);
        self.subscription_tier.push(_subscription_amount_2);
        self.token.write(IERC20Dispatcher { contract_address: _token_address });
    }


    #[abi(embed_v0)]
    impl TuneBridgeImpl of super::ITuneBridge<ContractState> {
        fn fetch_user(self: @ContractState, user_address: ContractAddress) -> UserState {
            // let user = get_caller_address();
            let current_time = get_block_timestamp();

            let existing_subscription = self.subscription.entry(user_address).read();
            // subscription.date != 0 && now_ts < subscription.date
            if existing_subscription.date != 00 && current_time < existing_subscription.date {
                return UserState {
                    amount: existing_subscription.clone().amount,
                    date: existing_subscription.clone().date,
                    user_address: user_address,
                };
            }

            return UserState { amount: 0, date: 0, user_address: user_address };
        }

        fn subscribe(ref self: ContractState, tier_index: u64) {
            let user = get_caller_address();
            let now_ts = get_block_timestamp();

            assert(tier_index < self.subscription_tier.len(), 'out of index scope');

            // Example: 30 days in seconds = 30 * 24 * 60 * 60
            let thirty_days: u64 = 30 * 24 * 60 * 60;
            let expiry = now_ts + thirty_days;

            if let Some(storage_ptr) = self.subscription_tier.get(tier_index) {
                let subscription_amount: u256 = storage_ptr.read();
                self
                    .collect_sell_token(
                        starknet::get_contract_address(),
                        user,
                        self.token.read(),
                        subscription_amount.into(),
                    );
                self
                    .subscription
                    .entry(user)
                    .write(ISubscription { amount: subscription_amount.into(), date: expiry });
            } else {
                // Handle the case where the index is out of bounds
                // For example, log an error or revert the transaction
                panic!("Invalid tier index");
            }
        }


        fn get_subscription_amount(self: @ContractState) -> Array<u256> {
            let mut amounts = array![];
            let len = self.subscription_tier.len();

            for i in 0..len {
                if let Some(storage_ptr) = self.subscription_tier.get(i) {
                    let amount: u256 = storage_ptr.read();
                    amounts.append(amount);
                }
            }

            return amounts;
        }

        fn add_subscription_amount(ref self: ContractState, amount: u256) {
            assert(self.is_owner(), 'unauthorized');
            self.subscription_tier.push(amount);
        }

        fn adjust_subscription_token(
            ref self: ContractState, new_token: ContractAddress, index: u64, new_amount: u256,
        ) {
            assert(self.is_owner(), 'unauthorized');
            self.token_address.write(new_token);

            if index < self.subscription_tier.len() {
                self.subscription_tier.at(index).write(new_amount);
            }
        }

        fn get_subscription_token(self: @ContractState) -> ContractAddress {
            let subscription_token = self.token_address.read();
            return subscription_token;
        }
    }

    #[generate_trait]
    impl SomeLogic of ILogic {
        fn collect_sell_token(
            ref self: ContractState,
            contract_address: ContractAddress,
            caller_address: ContractAddress,
            sell_token: IERC20Dispatcher,
            sell_token_amount: u256,
        ) {
            // Transfer tokens to contract
            assert(sell_token_amount > 0, 'Token from amount is 0');
            let sell_token_balance: u256 = sell_token
                .balance_of(caller_address)
                .try_into()
                .unwrap();
            assert(sell_token_balance >= sell_token_amount, 'Token from balance is too low');
            sell_token.transfer_from(caller_address, contract_address, sell_token_amount);
        }

        fn is_owner(ref self: ContractState) -> bool {
            if super::get_caller_address() == self.owner.read() {
                return true;
            }
            return false;
        }
    }
}
