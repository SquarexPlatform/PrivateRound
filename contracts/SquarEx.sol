pragma solidity ^0.4.12;


// ERC20 token interface is implemented only partially.
// Some functions left undefined:
//  - transfer, transferFrom,
//  - approve, allowance.
contract PresaleToken 
{
    string public constant name = "SquarEx Presale Token";
    string public constant symbol = "SQPT";
    uint public constant decimals = 18;
    uint public constant PRICE = 1000;  // per 1 Ether

    //  price
    // Cap is 2000 ETH
    // 1 eth = 1000 presale SQPT tokens
    // 
    // ETH price ~300$ for 30.06.2017
    uint public constant TOKEN_SUPPLY_LIMIT = 1000 * 2000 * (1 ether / 1 wei);

    /// @dev Constructor
    /// @param _tokenManager Token manager address.
    function PresaleToken(address _tokenManager, address _escrow) {
        tokenManager = _tokenManager;
        escrow = _escrow;
    }

    enum State{
       Init,
       Running,
       Paused,
       Migrating,
       Migrated
    }

    State public currentState = State.Init;
    uint public totalSupply = 0; // amount of tokens already sold

    // Token manager has exclusive priveleges to call administrative
    // functions on this contract.
    address public tokenManager;

    // Gathered funds can be withdrawn only to escrow's address.
    address public escrow;

    // Crowdsale manager has exclusive priveleges to burn presale tokens.
    address public crowdsaleManager;

    mapping (address => uint256) private balance;

    modifier onlyTokenManager()     { if(msg.sender != tokenManager) throw; _; }
    modifier onlyCrowdsaleManager() { if(msg.sender != crowdsaleManager) throw; _; }
    modifier onlyInState(State state){ if(state != currentState) throw; _; }

    event LogBuy(address indexed owner, uint value);
    event LogBurn(address indexed owner, uint value);
    event LogStateSwitch(State newState);

    /// @dev Lets buy you some tokens.
    function buyTokens(address _buyer) public payable onlyInState(State.Running){
        if(msg.value == 0) throw;
        uint newTokens = msg.value * PRICE;

        if (totalSupply + newTokens > TOKEN_SUPPLY_LIMIT) throw;

        balance[_buyer] += newTokens;
        totalSupply += newTokens;
        LogBuy(_buyer, newTokens);
    }


    /// @dev Returns number of tokens owned by given address.
    /// @param _owner Address of token owner.
    function burnTokens(address _owner) public onlyCrowdsaleManager onlyInState(State.Migrating)
    {
        uint tokens = balance[_owner];
        if(tokens == 0) throw;
        balance[_owner] = 0;
        totalSupply -= tokens;
        LogBurn(_owner, tokens);

        // Automatically switch phase when migration is done.
        if(totalSupply == 0) {
            currentState = State.Migrated;
            LogStateSwitch(State.Migrated);
        }
    }

    /// @dev Returns number of tokens owned by given address.
    /// @param _owner Address of token owner.
    function balanceOf(address _owner) constant returns (uint256) 
    {
        return balance[_owner];
    }

    function setPresaleState(State _nextState) public onlyTokenManager
    {
        bool canSwitchState
             =  (currentState == State.Init && _nextState == State.Running)
             || (currentState == State.Running && _nextState == State.Paused)
             // switch to migration phase only if crowdsale manager is set
             || ((currentState == State.Running || currentState == State.Paused)
                 && _nextState == State.Migrating
                 && crowdsaleManager != 0x0)
             || (currentState == State.Paused && _nextState == State.Running)
             // switch to migrated only if everyting is migrated
             || (currentState == State.Migrating && _nextState == State.Migrated
                 && totalSupply == 0);

        if(!canSwitchState) throw;

        currentState = _nextState;
        LogStateSwitch(_nextState);
    }

    function withdrawEther() public onlyTokenManager
    {
        if(this.balance > 0) {
            if(!escrow.send(this.balance)) throw;
        }
    }

    function setCrowdsaleManager(address _mgr) public onlyTokenManager
    {
        // You can't change crowdsale contract when migration is in progress.
        if(currentState == State.Migrating) throw;
        crowdsaleManager = _mgr;
    }

    // Default fallback function
    function() payable 
    {
        buyTokens(msg.sender);
    }

}
