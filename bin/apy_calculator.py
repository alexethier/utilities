#!/usr/bin/env python3
"""
Stock Option APY Calculator

Calculates the Annual Percentage Yield (APY) for stock options based on:
- Option symbol (e.g., SHOP270115P00140000)
- Current stock price
- Days until expiration
- Money required to cover the option
"""

import argparse
import re
from datetime import datetime, date
from typing import Tuple, Optional


def parse_option_symbol(symbol: str) -> Tuple[str, date, str, float]:
    """
    Parse an option symbol to extract components.
    
    Format: TICKER[YYMMDD][P/C][STRIKE_PRICE_PADDED]
    Example: SHOP270115P00140000
    - SHOP: ticker
    - 270115: January 15, 2027 (YYMMDD)
    - P: Put option
    - 00140000: Strike price $140.00 (padded to 8 digits, last 3 are decimals)
    
    Args:
        symbol: Option symbol string
        
    Returns:
        Tuple of (ticker, expiration_date, option_type, strike_price)
    """
    # Pattern to match option symbol format
    pattern = r'^([A-Z]+)(\d{6})([PC])(\d{8})$'
    match = re.match(pattern, symbol.upper())
    
    if not match:
        raise ValueError(f"Invalid option symbol format: {symbol}")
    
    ticker, date_str, option_type, strike_str = match.groups()
    
    # Parse date (YYMMDD format)
    year = int(date_str[:2])
    month = int(date_str[2:4])
    day = int(date_str[4:6])
    
    # Handle year (assume 20XX for years 00-99)
    if year >= 0:
        year += 2000
    
    expiration_date = date(year, month, day)
    
    # Parse strike price (8 digits, last 3 are decimal places)
    strike_price = int(strike_str) / 1000.0
    
    return ticker, expiration_date, option_type, strike_price


def calculate_days_to_expiration(expiration_date: date) -> int:
    """
    Calculate the number of days from today until expiration.
    
    Args:
        expiration_date: The expiration date of the option
        
    Returns:
        Number of days until expiration
    """
    today = date.today()
    days_to_expiry = (expiration_date - today).days
    
    if days_to_expiry < 0:
        raise ValueError(f"Option has already expired on {expiration_date}")
    
    return days_to_expiry


def calculate_coverage_amount(option_type: str, stock_price: float, strike_price: float) -> float:
    """
    Calculate the amount of money needed to cover the option.
    
    For calls: 100 * stock_price (money needed to buy 100 shares)
    For puts: 100 * strike_price (money needed to cover if assigned)
    
    Args:
        option_type: 'C' for call, 'P' for put
        stock_price: Current stock price
        strike_price: Strike price of the option
        
    Returns:
        Amount of money needed to cover the option
    """
    if option_type == 'C':
        return 100 * stock_price
    elif option_type == 'P':
        return 100 * strike_price
    else:
        raise ValueError(f"Invalid option type: {option_type}")


def calculate_apy(premium: float, coverage_amount: float, days_to_expiry: int) -> float:
    """
    Calculate the Annual Percentage Yield (APY) with compound interest.
    
    Formula: APY = (1 + periodic_rate)^(periods_per_year) - 1
    
    This calculates:
    1. Periodic rate = premium / coverage_amount (return for this period)
    2. Periods per year = 365 / days_to_expiry (how many such periods in a year)
    3. APY = (1 + periodic_rate)^(periods_per_year) - 1 (compound growth)
    4. Convert to percentage = APY * 100
    
    Args:
        premium: Option premium received
        coverage_amount: Money needed to cover the option
        days_to_expiry: Days until expiration
        
    Returns:
        APY as a percentage (accounts for compound interest)
    """
    if days_to_expiry <= 0:
        raise ValueError("Days to expiry must be positive")
    
    if coverage_amount <= 0:
        raise ValueError("Coverage amount must be positive")
    
    # Calculate APY with compound interest
    periodic_rate = premium / coverage_amount
    periods_per_year = 365 / days_to_expiry
    
    # APY = (1 + r)^n - 1, where r is periodic rate and n is periods per year
    apy_decimal = (1 + periodic_rate) ** periods_per_year - 1
    apy_percentage = apy_decimal * 100
    
    return apy_percentage


def main():
    parser = argparse.ArgumentParser(
        description="Calculate APY for stock options",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  %(prog)s -s SHOP270115P00140000 -c 145.50 -p 2.50
  %(prog)s --symbol AAPL240315C00150000 --current-price 148.75 --premium 3.25
  %(prog)s SHOP270115P00140000 145.50 --premium 2.50  # positional args still work

Note: Premium is per share. Total contract premium = premium × 100 shares
        """
    )
    
    parser.add_argument(
        'symbol',
        nargs='?',
        help='Option symbol (e.g., SHOP270115P00140000) - can also use --symbol/-s'
    )
    
    parser.add_argument(
        'stock_price',
        nargs='?',
        type=float,
        help='Current stock price - can also use --current-price/-c'
    )
    
    parser.add_argument(
        '-s', '--symbol',
        dest='symbol_flag',
        help='Option symbol (e.g., SHOP270115P00140000)'
    )
    
    parser.add_argument(
        '-c', '--current-price',
        dest='price_flag',
        type=float,
        help='Current stock price'
    )
    
    parser.add_argument(
        '-p', '--premium',
        type=float,
        help='Option premium per share (will be multiplied by 100 for total contract premium)'
    )
    
    args = parser.parse_args()
    
    try:
        # Determine symbol - use flag if provided, otherwise positional
        symbol = args.symbol_flag if args.symbol_flag else args.symbol
        if not symbol:
            parser.error("Option symbol is required. Use positional argument or --symbol/-s flag.")
        
        # Determine stock price - use flag if provided, otherwise positional
        stock_price = args.price_flag if args.price_flag is not None else args.stock_price
        if stock_price is None:
            parser.error("Stock price is required. Use positional argument or --current-price/-c flag.")
        
        # Parse the option symbol
        ticker, expiration_date, option_type, strike_price = parse_option_symbol(symbol)
        
        # Calculate days to expiration
        days_to_expiry = calculate_days_to_expiration(expiration_date)
        
        # Calculate coverage amount
        coverage_amount = calculate_coverage_amount(option_type, stock_price, strike_price)
        
        # Display parsed information
        option_type_full = "Put" if option_type == 'P' else "Call"
        print(f"Option Analysis for {symbol}")
        print(f"{'='*50}")
        print(f"Ticker:                 {ticker}")
        print(f"Option Type:            {option_type_full}")
        print(f"Strike Price:           ${strike_price:.2f}")
        print(f"Current Price:          ${stock_price:.2f}")
        print(f"Expiration:             {expiration_date.strftime('%B %d, %Y')}")
        print(f"Days to Expiry:         {days_to_expiry}")
        print(f"Coverage Amount:        ${coverage_amount:,.2f}")
        
        # Calculate APY if premium is provided
        if args.premium is not None:
            # Convert per-share premium to total contract premium (100 shares per contract)
            total_premium = args.premium * 100
            
            apy = calculate_apy(total_premium, coverage_amount, days_to_expiry)
            
            # Calculate compounding details for display
            periodic_rate = total_premium / coverage_amount
            periods_per_year = 365 / days_to_expiry
            
            print(f"Interest per period:    {periodic_rate * 100:.4g}%")
            print(f"Compounding periods/yr: {periods_per_year:.2f}")
            print(f"Total premium:          ${total_premium:.2f}")
            print(f"APY:                    {apy:.4g}%")
        else:
            print(f"\nTo calculate APY, provide --premium/-p option")
            print(f"Example: {parser.prog} -s {symbol} -c {stock_price} -p 2.50")
    
    except ValueError as e:
        print(f"Error: {e}")
        return 1
    except Exception as e:
        print(f"Unexpected error: {e}")
        return 1
    
    return 0


if __name__ == '__main__':
    exit(main())
