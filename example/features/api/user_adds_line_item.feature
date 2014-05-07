Feature: User adds line item
  To keep track of my deposits and debits
  I want to add line items to my register

  Scenario: Add deposit
    Given I have $20
    When I deposit $10
    Then I should have $30
