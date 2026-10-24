import { toIdentifier } from './entraNaming';

describe('toIdentifier', () => {
  it('turns Entra names into infrastructure identifiers', () => {
    expect(toIdentifier('jdoe')).toBe('jdoe');
    expect(toIdentifier('John.Doe')).toBe('john-doe');
    expect(toIdentifier('john_doe@acme.com')).toBe('john-doe-acme-com');
    expect(toIdentifier('Vision Research')).toBe('vision-research');
    expect(toIdentifier('9lives--x-')).toBe('lives-x');
    expect(toIdentifier('...')).toBeUndefined();
  });

  it('always matches the identifier rule', () => {
    for (const v of ['A.B', '__x__', 'x1.2y', 'Zoë Smith']) {
      expect(toIdentifier(v)).toMatch(/^[a-z][a-z0-9]*(-[a-z0-9]+)*$/);
    }
  });
});
